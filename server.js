const express = require('express');
const path = require('path');
const app = express();
app.use(express.json({limit:'1mb'}));
app.use(express.static(path.join(__dirname, 'public')));
app.get('/api/health', (_req,res)=>res.json({ok:true, app:'Devora-AI'}));
app.post('/api/chat', async (req,res)=>{
  try {
    const key = process.env.GROQ_API_KEY;
    if (!key) return res.status(503).json({error:'AI is not configured yet. Add GROQ_API_KEY in your hosting environment variables.'});
    const messages = Array.isArray(req.body.messages) ? req.body.messages : [];
    const safe = messages.filter(m=>m && ['user','assistant'].includes(m.role) && typeof m.content === 'string').slice(-24);
    if (!safe.length) return res.status(400).json({error:'Type a message to begin.'});
    const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method:'POST', headers:{'Authorization':'Bearer '+key,'Content-Type':'application/json'},
      body:JSON.stringify({model:process.env.GROQ_MODEL || 'openai/gpt-oss-120b',messages:[{role:'system',content:`You are Devora-AI, a highly capable, thoughtful AI assistant. Give accurate, useful, well-reasoned answers tailored to the user's actual request. First identify the user's goal and answer it directly. Be clear, natural, friendly, and confident without pretending to know things you do not know. For simple questions, be concise; for complex tasks, provide a thorough, well-organized answer with headings, numbered steps, examples, and practical next actions where useful. Explain difficult ideas in plain language without talking down to the user. For coding tasks, provide complete, runnable solutions when practical, explain where code belongs, account for edge cases, and never claim to have tested, deployed, changed files, or accessed systems unless that actually happened. For troubleshooting, diagnose likely causes systematically and give actionable fixes. For writing requests, produce polished ready-to-use text in the requested tone. For comparisons or recommendations, explain trade-offs and state assumptions. Ask a focused clarifying question only when essential; otherwise make reasonable assumptions and state them briefly. Do not invent facts, citations, links, tool results, or current information. Be transparent about uncertainty and limitations, distinguish verified facts from suggestions, and correct misconceptions respectfully. Avoid repetitive introductions, filler, generic disclaimers, and unnecessarily long conclusions. Format answers for easy reading, using Markdown when it helps. Follow safety requirements and protect private information. When the user asks for a specific output, prioritize delivering that output over explaining how you would do it.`},...safe],temperature:0.65,max_tokens:4096})
    });
    const data = await response.json();
    if (!response.ok) return res.status(response.status).json({error:data?.error?.message || 'AI provider request failed.'});
    res.json({reply:data.choices?.[0]?.message?.content || 'I could not generate a response.'});
  } catch (e) { res.status(500).json({error:'Could not reach the AI service. Please try again.'}); }
});

const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const { spawn } = require('child_process');
let ffmpegPath;
try { ffmpegPath = require('ffmpeg-static'); } catch (_) { ffmpegPath = null; }
const movieJobs = new Map();
app.post('/api/movie/storyboard', async (req,res) => {
  try {
    const key=process.env.GROQ_API_KEY;
    if(!key)return res.status(503).json({error:'GROQ_API_KEY is required to write a movie storyboard.'});
    const prompt=typeof req.body.prompt==='string'?req.body.prompt.trim().slice(0,4000):'';
    const count=Math.max(1,Math.min(60,Number.parseInt(req.body.count,10)||12));
    const offset=Math.max(0,Math.min(1079,Number.parseInt(req.body.offset,10)||0));
    const total=Math.max(count,Math.min(1080,Number.parseInt(req.body.total,10)||count));
    const minutes=Math.max(1,Math.min(180,Number.parseInt(req.body.minutes,10)||1));
    const mode=req.body.mode==='smart'?'smart':'full';
    if(!prompt)return res.status(400).json({error:'Enter a movie idea.'});
    const response=await fetch('https://api.groq.com/openai/v1/chat/completions',{method:'POST',headers:{'Authorization':'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({model:process.env.GROQ_MODEL||'openai/gpt-oss-120b',temperature:0.7,max_tokens:Math.min(8000,500+count*100),response_format:{type:'json_object'},messages:[{role:'system',content:'You are a film screenwriter and storyboard artist. Return valid JSON only, shaped as {"scenes":[{"title":"short title","description":"visual action for this scene","continuity":"details that should stay consistent","camera":"shot and camera movement","mood":"mood"}]}. Make scenes sequential, visually distinct, coherent, and keep characters, wardrobe and locations consistent. No markdown.'},{role:'user',content:'Create exactly '+count+' storyboard scenes for this movie concept: '+prompt+'. These are scenes '+(offset+1)+' through '+(offset+count)+' of '+total+' total scenes for a '+minutes+' minute film. Production mode: '+mode+'. Keep this batch consistent with a single continuous film and avoid repeating earlier generic beats. Scene numbers should follow the requested global range. Each scene must be visually producible as one short clip or one keyframe image.'}]})});
    const data=await response.json();if(!response.ok)return res.status(response.status).json({error:data?.error?.message||'Storyboard model request failed.'});
    let parsed;try{parsed=JSON.parse(data.choices?.[0]?.message?.content||'{}')}catch(_){return res.status(502).json({error:'AI returned an invalid storyboard. Please retry.'})}
    if(!Array.isArray(parsed.scenes)||!parsed.scenes.length)return res.status(502).json({error:'AI did not return storyboard scenes.'});
    res.json({scenes:parsed.scenes.slice(0,count)});
  }catch(e){res.status(500).json({error:'Could not create storyboard. Please retry.'})}
});
function safeMovieUrl(value){try{const u=new URL(value);return u.protocol==='https:'&&!['localhost','127.0.0.1','0.0.0.0','::1'].includes(u.hostname)&&!u.hostname.endsWith('.local')}catch(_){return false}}
function runFfmpeg(args){return new Promise((resolve,reject)=>{if(!ffmpegPath)return reject(new Error('FFmpeg is unavailable. Check the Render build logs.'));const child=spawn(ffmpegPath,args,{stdio:['ignore','ignore','pipe']});let err='';child.stderr.on('data',d=>{err+=d.toString();if(err.length>6000)err=err.slice(-6000)});child.on('error',reject);child.on('close',code=>code===0?resolve():reject(new Error(err.slice(-1200)||'FFmpeg failed')));})}
async function downloadMovieAsset(url,dest){if(!safeMovieUrl(url))throw new Error('A scene URL was invalid.');const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),90000);try{const r=await fetch(url,{signal:controller.signal,redirect:'follow'});if(!r.ok)throw new Error('Could not download a generated scene (HTTP '+r.status+').');const type=(r.headers.get('content-type')||'').toLowerCase();if(!type.startsWith('video/')&&!type.startsWith('image/'))throw new Error('A generated scene URL did not return video or image media.');const bytes=Buffer.from(await r.arrayBuffer());if(bytes.length>100*1024*1024)throw new Error('A scene is larger than the 100 MB rendering limit.');await fs.promises.writeFile(dest,bytes);return type.startsWith('image/')?'image':'video'}finally{clearTimeout(timer)}}
app.post('/api/movie/assemble',async(req,res)=>{
 try{
  if(!ffmpegPath)return res.status(503).json({error:'The MP4 renderer is not installed. Redeploy after ffmpeg-static is added.'});
  const segments=Array.isArray(req.body.segments)?req.body.segments:[];
  if(!segments.length||segments.length>1080)return res.status(400).json({error:'Provide between 1 and 1,080 generated scenes.'});
  for(const s of segments)if(!s||!safeMovieUrl(s.url)||!['image','video'].includes(s.mediaType))return res.status(400).json({error:'A scene URL or media type is invalid.'});
  const id=crypto.randomUUID(),dir=path.join(os.tmpdir(),'devora-movie-'+id),publicDir=path.join(__dirname,'public','movie-renders');await fs.promises.mkdir(dir,{recursive:true});await fs.promises.mkdir(publicDir,{recursive:true});
  const job={state:'queued',progress:0,url:null,error:null,createdAt:Date.now()};movieJobs.set(id,job);res.status(202).json({jobId:id,state:'queued'});
  (async()=>{try{
   const list=[];
   for(let i=0;i<segments.length;i++){
    job.state='rendering';job.progress=Math.round((i/segments.length)*70);
    const s=segments[i],ext=s.mediaType==='image'?'jpg':'mp4',input=path.join(dir,'input-'+String(i).padStart(4,'0')+'.'+ext),output=path.join(dir,'segment-'+String(i).padStart(4,'0')+'.mp4');
    const actual=await downloadMovieAsset(s.url,input);
    if(actual==='image'){
     const dur=Math.max(3,Math.min(3600,Number(s.durationSeconds)||5)),ratio=String(req.body.aspectRatio||'16:9'),w=ratio==='9:16'?720:1280,h=ratio==='9:16'?1280:ratio==='1:1'?720:720;
     const vf='scale='+w+':'+h+':force_original_aspect_ratio=decrease,pad='+w+':'+h+':(ow-iw)/2:(oh-ih)/2,zoompan=z=min(zoom+0.0005\,1.08):d=1:s='+w+'x'+h+':fps=24,format=yuv420p';
     await runFfmpeg(['-y','-loop','1','-i',input,'-t',String(dur),'-vf',vf,'-r','24','-c:v','libx264','-preset','ultrafast','-movflags','+faststart',output]);
    }else{
     const ratio=String(req.body.aspectRatio||'16:9'),w=ratio==='9:16'?720:1280,h=ratio==='9:16'?1280:ratio==='1:1'?720:720;
     const clipDuration=Math.max(1,Math.min(3600,Number(s.durationSeconds)||10));await runFfmpeg(['-y','-stream_loop','-1','-i',input,'-t',String(clipDuration),'-vf','scale='+w+':'+h+':force_original_aspect_ratio=decrease,pad='+w+':'+h+':(ow-iw)/2:(oh-ih)/2,setsar=1,fps=24,format=yuv420p','-an','-c:v','libx264','-preset','ultrafast','-movflags','+faststart',output]);
    }
    list.push(output);job.progress=Math.round(((i+1)/segments.length)*70);
   }
   const concat=path.join(dir,'concat.txt');await fs.promises.writeFile(concat,list.map(f=>"file '"+f.replace(/'/g,"'\\''")+"'").join('\n'));
   const target=path.join(publicDir,id+'.mp4');job.state='finalizing';await runFfmpeg(['-y','-f','concat','-safe','0','-i',concat,'-c','copy','-movflags','+faststart',target]);
   job.state='completed';job.progress=100;job.url='/movie-renders/'+id+'.mp4';job.finishedAt=Date.now();
  }catch(e){job.state='failed';job.error=e.message||'Movie rendering failed.';job.finishedAt=Date.now();console.error('Movie assembly failed:',e)}finally{setTimeout(()=>fs.promises.rm(dir,{recursive:true,force:true}).catch(()=>{}),60000)}})();
 }catch(e){res.status(500).json({error:e.message||'Could not queue movie rendering.'})}
});
app.get('/api/movie/assemble/:id',(req,res)=>{const job=movieJobs.get(req.params.id);if(!job)return res.status(404).json({error:'Movie job not found; the server may have restarted.',state:'failed'});res.json({state:job.state,progress:job.progress,url:job.url,error:job.error})});

const port = process.env.PORT || 3000;
app.listen(port,'0.0.0.0',()=>console.log('Devora-AI running on '+port));
