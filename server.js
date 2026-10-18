const express = require('express');
const path = require('path');
const app = express();
app.use(express.json({limit:'1mb'}));
app.use(express.static(path.join(__dirname, 'public')));
app.get('/api/health', (_req,res)=>res.json({ok:true, app:'Devora-AI'}));

const FLUTTERWAVE_PACKAGES = {5000:1000,10000:2000,15000:3000,20000:4000,25000:5000,30000:6000,35000:7000,40000:8000,45000:9000,50000:10000,55000:11000,60000:12000};
async function supabaseRest(ctx, pathname, options={}) {
  const response=await fetch(ctx.base+pathname,{...options,headers:{apikey:ctx.service,Authorization:'Bearer '+ctx.service,'Content-Type':'application/json',...(options.headers||{})}});
  const text=await response.text();let data=null;try{data=text?JSON.parse(text):null}catch(_){}
  if(!response.ok)throw new Error((data&& (data.message||data.error||data.hint))||'Supabase request failed.');
  return data;
}
app.post('/api/payments/flutterwave/initialize',async(req,res)=>{
 try{
  const ctx=await verifySupabaseUser(req);
  if(!process.env.FLW_SECRET_KEY)return res.status(503).json({error:'Flutterwave is not configured. Add FLW_SECRET_KEY to Render environment variables.'});
  const amount=Number(req.body&&req.body.amountNgn),credits=FLUTTERWAVE_PACKAGES[amount];
  if(!credits)return res.status(400).json({error:'Choose one of the available top-up packages.'});
  const profile=await supabaseRest(ctx,'/auth/v1/user',{headers:{apikey:process.env.SUPABASE_ANON_KEY||process.env.SUPABASE_PUBLISHABLE_KEY,Authorization:req.headers.authorization}});
  const reference='devora_'+ctx.user.id.replace(/-/g,'').slice(0,12)+'_'+crypto.randomUUID().replace(/-/g,'');
  const pending=await supabaseRest(ctx,'/rest/v1/devora_credit_purchases',{method:'POST',headers:{Prefer:'return=representation'},body:JSON.stringify({user_id:ctx.user.id,reference,amount_ngn:amount,credits,status:'pending',provider:'flutterwave'})});
  const email=profile.email||ctx.user.email;
  if(!email)throw new Error('Your account needs an email address before payment.');
  const origin=(process.env.PUBLIC_APP_URL||'https://devora-ai-zcmz.onrender.com').replace(/\/$/,'');
  const fw=await fetch('https://api.flutterwave.com/v3/payments',{method:'POST',headers:{Authorization:'Bearer '+process.env.FLW_SECRET_KEY,'Content-Type':'application/json'},body:JSON.stringify({tx_ref:reference,amount:String(amount),currency:'NGN',redirect_url:origin+'/?payment=flutterwave',customer:{email,name:profile.user_metadata?.full_name||profile.user_metadata?.name||'Devora AI user'},customizations:{title:'Devora AI Credits',description:credits+' generation credits',logo:origin+'/favicon.ico'},meta:{user_id:ctx.user.id,credits}})});
  const data=await fw.json();
  if(!fw.ok||data.status!=='success'||!data.data?.link){await supabaseRest(ctx,'/rest/v1/devora_credit_purchases?reference=eq.'+encodeURIComponent(reference),{method:'PATCH',body:JSON.stringify({status:'failed'})}).catch(()=>{});return res.status(502).json({error:data.message||'Flutterwave could not start checkout.'});}
  res.json({success:true,checkoutUrl:data.data.link,reference,amountNgn:amount,credits});
 }catch(e){res.status(e.status||500).json({error:e.message||'Could not start payment.'});}
});
app.post('/api/payments/flutterwave/verify',async(req,res)=>{
 try{
  const ctx=await verifySupabaseUser(req);
  if(!process.env.FLW_SECRET_KEY)return res.status(503).json({error:'Flutterwave is not configured.'});
  const transactionId=String(req.body?.transaction_id||'').trim(),reference=String(req.body?.tx_ref||'').trim();
  if(!/^\d+$/.test(transactionId)||!/^devora_[a-zA-Z0-9_]+$/.test(reference))return res.status(400).json({error:'Invalid payment reference.'});
  const purchases=await supabaseRest(ctx,'/rest/v1/devora_credit_purchases?select=*&reference=eq.'+encodeURIComponent(reference)+'&user_id=eq.'+encodeURIComponent(ctx.user.id),{});
  const purchase=Array.isArray(purchases)?purchases[0]:null;
  if(!purchase)return res.status(404).json({error:'Payment record not found for this account.'});
  if(purchase.status==='successful')return res.json({success:true,alreadyProcessed:true,creditsAdded:purchase.credits,amountNgn:Number(purchase.amount_ngn)});
  const response=await fetch('https://api.flutterwave.com/v3/transactions/'+encodeURIComponent(transactionId)+'/verify',{headers:{Authorization:'Bearer '+process.env.FLW_SECRET_KEY,Accept:'application/json'}});
  const verification=await response.json(),tx=verification.data||{};
  if(!response.ok||verification.status!=='success'||tx.status!=='successful'||String(tx.tx_ref)!==reference||String(tx.currency).toUpperCase()!=='NGN'||Math.round(Number(tx.amount))!==Math.round(Number(purchase.amount_ngn))){
   return res.status(402).json({error:'Payment is not verified as successful for the exact amount. If you have paid, wait briefly and retry.'});
  }
  const completed=await supabaseRest(ctx,'/rest/v1/rpc/devora_complete_credit_purchase',{method:'POST',body:JSON.stringify({p_reference:reference,p_user_id:ctx.user.id,p_amount_ngn:Number(tx.amount),p_transaction_id:String(tx.id)})});
  res.json({success:true,creditsAdded:completed?.creditsAdded??purchase.credits,balance:completed?.balance});
 }catch(e){res.status(e.status||500).json({error:e.message||'Could not verify payment.'});}
});


const dns = require('dns').promises;
const net = require('net');
const STORAGE_BUCKET = 'devora-assets';
const STORAGE_MAX_BYTES = 200 * 1024 * 1024;
function isPublicIp(ip) {
  if (net.isIP(ip) === 4) {
    const p=ip.split('.').map(Number);
    return !(p[0]===10 || p[0]===127 || p[0]===0 || (p[0]===169&&p[1]===254) || (p[0]===172&&p[1]>=16&&p[1]<=31) || (p[0]===192&&p[1]===168) || (p[0]===100&&p[1]>=64&&p[1]<=127) || p[0]>=224);
  }
  if (net.isIP(ip) === 6) {
    const x=ip.toLowerCase();
    return x==='::1' ? false : !(x==='::' || x.startsWith('fe8') || x.startsWith('fe9') || x.startsWith('fea') || x.startsWith('feb') || x.startsWith('fc') || x.startsWith('fd') || x.startsWith('ff'));
  }
  return false;
}
function importHosts() {
  return (process.env.STORAGE_IMPORT_HOSTS||'').split(',').map(x=>x.trim().toLowerCase()).filter(Boolean);
}
async function validateImportUrl(raw) {
  let u;
  try { u=new URL(raw); } catch (_) { throw new Error('Invalid media URL.'); }
  if (u.protocol!=='https:' || u.username || u.password || u.port && u.port!=='443') throw new Error('Only public HTTPS media URLs are supported.');
  const host=u.hostname.toLowerCase();
  const allowed=importHosts();
  if (!allowed.some(h=>h.startsWith('*.') ? host.endsWith(h.slice(1)) && host!==h.slice(2) : host===h)) throw new Error('This media host is not allowed yet. Add its hostname to STORAGE_IMPORT_HOSTS in Render.');
  const addresses=await dns.lookup(host,{all:true,verbatim:true});
  if (!addresses.length || addresses.some(a=>!isPublicIp(a.address))) throw new Error('Media URL resolves to a non-public address and was blocked.');
  return u;
}
async function fetchImportBytes(raw) {
  let url=raw;
  for(let hop=0;hop<=3;hop++) {
    const u=await validateImportUrl(url);
    const response=await fetch(u,{redirect:'manual',signal:AbortSignal.timeout(120000)});
    if([301,302,303,307,308].includes(response.status)) {
      const location=response.headers.get('location');
      if(!location || hop===3) throw new Error('Too many or invalid media redirects.');
      url=new URL(location,u).href;
      continue;
    }
    if(!response.ok) throw new Error('Media provider returned HTTP '+response.status+'.');
    const declared=Number(response.headers.get('content-length')||0);
    if(declared>STORAGE_MAX_BYTES) throw new Error('Media is larger than the 200 MB storage-import limit.');
    const type=(response.headers.get('content-type')||'application/octet-stream').split(';')[0].trim().toLowerCase();
    const allowedType=/^(image\/(png|jpeg|webp|gif|avif)|video\/(mp4|webm|quicktime|mpeg)|audio\/(mpeg|mp4|wav|webm|ogg|aac|flac)|application\/(zip|pdf|json|octet-stream)|text\/(plain|csv|markdown|html|css|javascript))$/.test(type);
    if(!allowedType) throw new Error('Unsupported media content type: '+type);
    if(!response.body) throw new Error('Media provider returned an empty response.');
    const chunks=[];let total=0;
    for await (const chunk of response.body) { const b=Buffer.from(chunk);total+=b.length;if(total>STORAGE_MAX_BYTES){response.body.cancel().catch(()=>{});throw new Error('Media is larger than the 200 MB storage-import limit.');}chunks.push(b); }
    if(!total) throw new Error('The media file is empty.');
    return {buffer:Buffer.concat(chunks),type,size:total,url:u.href};
  }
  throw new Error('Could not safely fetch the media URL.');
}
async function verifySupabaseUser(req) {
  const base=(process.env.SUPABASE_URL||'').replace(/\/$/,'');
  const anon=process.env.SUPABASE_ANON_KEY||process.env.SUPABASE_PUBLISHABLE_KEY||'';
  const service=process.env.SUPABASE_SERVICE_ROLE_KEY||'';
  const auth=(req.headers.authorization||'').match(/^Bearer\s+(.+)$/i);
  if(!base||!anon||!service) throw Object.assign(new Error('Supabase server storage is not configured. Add SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY to Render environment variables.'),{status:503});
  if(!auth) throw Object.assign(new Error('Sign in again to save this file.'),{status:401});
  const r=await fetch(base+'/auth/v1/user',{headers:{apikey:anon,Authorization:'Bearer '+auth[1]}});
  if(!r.ok) throw Object.assign(new Error('Your session is invalid or expired. Sign in again.'),{status:401});
  const user=await r.json();if(!user||!user.id)throw Object.assign(new Error('Could not verify the signed-in user.'),{status:401});
  return {base,service,user};
}
app.get('/api/storage/health',(_req,res)=>{
  res.json({ok:true,configured:!!(process.env.SUPABASE_URL&&(process.env.SUPABASE_ANON_KEY||process.env.SUPABASE_PUBLISHABLE_KEY)&&process.env.SUPABASE_SERVICE_ROLE_KEY),bucket:STORAGE_BUCKET,importHostsConfigured:importHosts().length>0,maxImportBytes:STORAGE_MAX_BYTES});
});
app.post('/api/storage/import',async(req,res)=>{
  let uploadedPath=null;let storageContext=null;
  try {
    storageContext=await verifySupabaseUser(req);
    const {url,name,assetType,metadata}=req.body||{};
    if(typeof url!=='string'||url.length>4096) return res.status(400).json({error:'Provide a valid media URL.'});
    const validTypes=['upload','generated_image','generated_video','generated_music','movie','other'];
    const kind=validTypes.includes(assetType)?assetType:'other';
    const media=await fetchImportBytes(url);
    const rawName=typeof name==='string'?name:'asset';
    const clean=rawName.replace(/[^a-zA-Z0-9._-]/g,'_').slice(-140)||'asset';
    const objectPath=storageContext.user.id+'/'+Date.now()+'-'+crypto.randomUUID()+'-'+clean;
    const upload=await fetch(storageContext.base+'/storage/v1/object/'+STORAGE_BUCKET+'/'+objectPath.split('/').map(encodeURIComponent).join('/'),{
      method:'POST',headers:{apikey:storageContext.service,Authorization:'Bearer '+storageContext.service,'Content-Type':media.type,'x-upsert':'false'},body:media.buffer,signal:AbortSignal.timeout(120000)
    });
    if(!upload.ok) { const t=(await upload.text()).slice(0,500);throw new Error('Supabase Storage upload failed: '+t); }
    uploadedPath=objectPath;
    const row={user_id:storageContext.user.id,bucket_id:STORAGE_BUCKET,object_path:objectPath,asset_type:kind,mime_type:media.type,original_name:rawName.slice(0,255),size_bytes:media.size,metadata:{...(metadata&&typeof metadata==='object'&&!Array.isArray(metadata)?metadata:{}),source_url:media.url,stored_server_side:true}};
    const saved=await fetch(storageContext.base+'/rest/v1/devora_assets',{method:'POST',headers:{apikey:storageContext.service,Authorization:'Bearer '+storageContext.service,'Content-Type':'application/json',Prefer:'return=representation'},body:JSON.stringify(row)});
    if(!saved.ok) { await fetch(storageContext.base+'/storage/v1/object/'+STORAGE_BUCKET+'/'+objectPath.split('/').map(encodeURIComponent).join('/'),{method:'DELETE',headers:{apikey:storageContext.service,Authorization:'Bearer '+storageContext.service}}).catch(()=>{});uploadedPath=null;throw new Error('File uploaded, but its library record could not be saved: '+(await saved.text()).slice(0,400)); }
    const rows=await saved.json();
    res.status(201).json({ok:true,asset:rows[0],path:objectPath,size:media.size,mimeType:media.type});
  } catch(e) { res.status(e.status||500).json({error:e.message||'Could not save media to Supabase.'}); }
});

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
