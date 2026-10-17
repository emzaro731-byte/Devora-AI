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
      body:JSON.stringify({model:process.env.GROQ_MODEL || 'llama-3.3-70b-versatile',messages:[{role:'system',content:'You are Devora-AI, a helpful, clear, capable assistant. Answer naturally, be honest about uncertainty, and provide useful steps and code when appropriate.'},...safe],temperature:0.7,max_tokens:2048})
    });
    const data = await response.json();
    if (!response.ok) return res.status(response.status).json({error:data?.error?.message || 'AI provider request failed.'});
    res.json({reply:data.choices?.[0]?.message?.content || 'I could not generate a response.'});
  } catch (e) { res.status(500).json({error:'Could not reach the AI service. Please try again.'}); }
});
const port = process.env.PORT || 3000;
app.listen(port,'0.0.0.0',()=>console.log('Devora-AI running on '+port));
