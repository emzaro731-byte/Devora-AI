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
const port = process.env.PORT || 3000;
app.listen(port,'0.0.0.0',()=>console.log('Devora-AI running on '+port));
