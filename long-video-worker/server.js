const http = require('node:http');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const SUPABASE_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const PROVIDER_FUNCTION = '/functions/v1/devora-worker-provider';
const PORT = Number(process.env.PORT || 10000);
const BUCKET = process.env.OUTPUT_BUCKET || 'devora-long-videos';
const POLL_MS = Number(process.env.POLL_MS || 5000);
const MAX_MINUTES = 60;
let busy = false;

function required() {
  const missing = [['SUPABASE_URL', SUPABASE_URL], ['SUPABASE_SERVICE_ROLE_KEY', SERVICE_KEY]].filter(x => !x[1]).map(x => x[0]);
  if (missing.length) throw new Error('Missing environment variables: ' + missing.join(', '));
}
async function sb(pathname, options = {}) {
  const r = await fetch(SUPABASE_URL + pathname, { ...options, headers: {
    apikey: SERVICE_KEY, Authorization: 'Bearer ' + SERVICE_KEY, 'Content-Type': 'application/json', ...(options.headers || {})
  }});
  const text = await r.text();
  let data; try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  if (!r.ok) throw new Error('Supabase ' + r.status + ': ' + (data?.message || data?.error || text).toString().slice(0, 500));
  return data;
}
async function patchProject(id, values) {
  values.updated_at = new Date().toISOString();
  await sb('/rest/v1/devora_long_video_projects?id=eq.' + encodeURIComponent(id), { method: 'PATCH', body: JSON.stringify(values), headers: { Prefer: 'return=minimal' } });
}
async function provider(action, payload = {}) {
  const response = await fetch(SUPABASE_URL + PROVIDER_FUNCTION, {
    method: 'POST',
    headers: { apikey: SERVICE_KEY, Authorization: 'Bearer ' + SERVICE_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, ...payload }),
  });
  const raw = await response.text();
  let data; try { data = raw ? JSON.parse(raw) : {}; } catch { throw new Error('Supabase provider function returned invalid JSON.'); }
  if (!response.ok || data.error) throw new Error(String(data.error || ('Provider request failed (' + response.status + ')')).slice(0, 1000));
  return data;
}
async function groqScenes(prompt, total, resolution) {
  const all = [];
  for (let start = 0; start < total; start += 20) {
    const count = Math.min(20, total - start);
    const data = await provider('plan-scenes', {
      prompt, total: count, resolution, firstSceneNumber: start + 1,
      continuityNote: all.length
        ? 'Continue the same story and visual identity from these previous scene summaries: ' + all.slice(-5).map(s => s.prompt).join(' | ')
        : 'Establish the main characters and visual style in the opening scenes.',
    });
    if (!Array.isArray(data.scenes) || data.scenes.length !== count || data.scenes.some(s => typeof s.prompt !== 'string' || !s.prompt.trim())) {
      throw new Error('Supabase scene planner returned an incomplete scene list.');
    }
    all.push(...data.scenes.map((s, i) => ({
      scene: start + i + 1, prompt: s.prompt.trim().slice(0, 4000),
      continuity: String(s.continuity || '').slice(0, 500), status: 'queued', taskId: null, url: null,
    })));
  }
  return all;
}
function run(command, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { ...opts, stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';
    child.stderr.on('data', b => { stderr = (stderr + b.toString()).slice(-5000); });
    child.on('error', reject);
    child.on('close', code => code === 0 ? resolve() : reject(new Error(command + ' failed: ' + stderr.slice(-1500))));
  });
}
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function kieCreate(prompt, resolution, aspectRatio) {
  const data = await provider('kie-create', { prompt, resolution, aspectRatio });
  const taskId = data.taskId;
  if (!taskId) throw new Error('KIE did not return a task ID for a clip.');
  return taskId;
}
async function kiePoll(taskId, maxMs = 45 * 60 * 1000) {
  const started = Date.now();
  while (Date.now() - started < maxMs) {
    await sleep(5000);
    const task = await provider('kie-poll', { taskId });
    if (task.state === 'success' && task.url) {
      return { url: task.url, creditsConsumed: Number(task.creditsConsumed ?? 0) || null };
    }
    if (['fail', 'failed', 'error'].includes(String(task.state).toLowerCase())) {
      throw new Error('KIE clip failed: ' + (task.failMsg || 'provider error'));
    }
  }
  throw new Error('A clip timed out while waiting for KIE. The project is stopped to prevent untracked costs.');
}
async function ensureBucket() {
  const r = await fetch(SUPABASE_URL + '/storage/v1/bucket/' + BUCKET, { headers: { apikey: SERVICE_KEY, Authorization: 'Bearer ' + SERVICE_KEY } });
  if (r.ok) return;
  const create = await fetch(SUPABASE_URL + '/storage/v1/bucket', { method: 'POST', headers: { apikey: SERVICE_KEY, Authorization: 'Bearer ' + SERVICE_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ id: BUCKET, name: BUCKET, public: false, file_size_limit: 8 * 1024 * 1024 * 1024, allowed_mime_types: ['video/mp4'] }) });
  if (!create.ok && create.status !== 409) throw new Error('Could not create private video storage bucket: ' + (await create.text()).slice(0, 400));
}
async function uploadOutput(id, userId, file) {
  await ensureBucket();
  const objectPath = userId + '/' + id + '.mp4';
  const bytes = await fs.readFile(file);
  const r = await fetch(SUPABASE_URL + '/storage/v1/object/' + BUCKET + '/' + objectPath, {
    method: 'POST', headers: { apikey: SERVICE_KEY, Authorization: 'Bearer ' + SERVICE_KEY, 'Content-Type': 'video/mp4', 'x-upsert': 'true' }, body: bytes
  });
  if (!r.ok) throw new Error('Could not upload finished MP4: ' + (await r.text()).slice(0, 400));
  const signed = await fetch(SUPABASE_URL + '/storage/v1/object/sign/' + BUCKET + '/' + objectPath, {
    method: 'POST', headers: { apikey: SERVICE_KEY, Authorization: 'Bearer ' + SERVICE_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ expiresIn: 604800 })
  });
  if (!signed.ok) throw new Error('Video was assembled but a download link could not be created.');
  const data = await signed.json();
  const signedPath = data.signedURL || data.signedUrl;
  if (!signedPath) throw new Error('Storage did not return a download link.');
  return signedPath.startsWith('http') ? signedPath : SUPABASE_URL + '/storage/v1' + (signedPath.startsWith('/') ? signedPath : '/' + signedPath);
}
async function processProject(project) {
  const id = project.id;
  const userId = project.user_id;
  const minutes = Math.ceil(Number(project.target_duration_seconds) / 60);
  if (!project.prompt || project.target_duration_seconds < 60 || project.target_duration_seconds > MAX_MINUTES * 60) throw new Error('Invalid project duration or prompt.');
  if (project.model !== 'bytedance/seedance-2-5') throw new Error('Only Seedance 2.5 is currently supported for long-video projects.');
  if (!['480p', '720p', '1080p'].includes(project.resolution)) throw new Error('Invalid resolution.');
  const rate = { '480p': 28, '720p': 63, '1080p': 158 }[project.resolution];
  const estimate = rate * project.target_duration_seconds;
  await patchProject(id, { status: 'planning', estimated_credits: estimate, error_message: null });
  // 15-second clips: the last clip is trimmed to the exact requested duration.
  const total = Math.ceil(project.target_duration_seconds / 15);
  const scenes = await groqScenes(project.prompt, total, project.resolution);
  await patchProject(id, { status: 'generating', scenes, total_scenes: total, completed_scenes: 0 });
  const workDir = await fs.mkdtemp(path.join(os.tmpdir(), 'devora-long-' + id + '-'));
  try {
    const clipFiles = [];
    for (let i = 0; i < scenes.length; i++) {
      const scene = scenes[i];
      // Scene list stays in backend; the app only receives project-level progress.
      const taskId = await kieCreate(scene.prompt + (scene.continuity ? '\nContinuity: ' + scene.continuity : ''), project.resolution, project.aspect_ratio);
      scenes[i] = { ...scene, status: 'generating', taskId };
      await patchProject(id, { scenes, completed_scenes: i, status: 'generating' });
      const clip = await kiePoll(taskId);
      const clipPath = path.join(workDir, 'clip-' + String(i).padStart(4, '0') + '.mp4');
      const download = await fetch(clip.url);
      if (!download.ok) throw new Error('Could not download generated clip ' + (i + 1) + '.');
      await fs.writeFile(clipPath, Buffer.from(await download.arrayBuffer()));
      clipFiles.push(clipPath);
      scenes[i] = { ...scene, status: 'completed', taskId, creditsConsumed: clip.creditsConsumed };
      await patchProject(id, { scenes, completed_scenes: i + 1, status: 'generating' });
    }
    await patchProject(id, { status: 'assembling' });
    const listPath = path.join(workDir, 'concat.txt');
    await fs.writeFile(listPath, clipFiles.map(p => "file '" + p.replace(/'/g, "'\\''") + "'").join('\n'));
    const output = path.join(workDir, 'devora-final.mp4');
    await run('ffmpeg', ['-y', '-f', 'concat', '-safe', '0', '-i', listPath, '-t', String(project.target_duration_seconds), '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', output]);
    const outputUrl = await uploadOutput(id, userId, output);
    await patchProject(id, { status: 'completed', output_url: outputUrl, completed_scenes: total, scenes, error_message: null });
  } finally {
    await fs.rm(workDir, { recursive: true, force: true }).catch(() => {});
  }
}
async function tick() {
  if (busy) return;
  busy = true;
  try {
    const queued = await sb('/rest/v1/devora_long_video_projects?status=eq.queued&select=*&order=created_at.asc&limit=1');
    if (!queued?.length) return;
    const project = queued[0];
    // Single worker process claims one job; a database update protects UI progress.
    await patchProject(project.id, { status: 'planning', error_message: null });
    try { await processProject({ ...project, status: 'planning' }); }
    catch (e) { console.error('Long-video project failed:', project.id, e); await patchProject(project.id, { status: 'failed', error_message: String(e.message || e).slice(0, 1500) }).catch(() => {}); }
  } catch (e) { console.error('Worker poll failed:', e.message || e); }
  finally { busy = false; }
}
const server = http.createServer((req, res) => {
  if (req.url === '/health') { res.writeHead(200, { 'content-type': 'application/json' }); return res.end(JSON.stringify({ ok: true, busy, service: 'devora-long-video-worker' })); }
  res.writeHead(404, { 'content-type': 'application/json' }); res.end(JSON.stringify({ error: 'Not found' }));
});
try { required(); } catch (e) { console.error(e.message); process.exit(1); }
server.listen(PORT, () => { console.log('Devora long-video worker listening on ' + PORT); tick(); setInterval(tick, POLL_MS); });
