# Devora-AI

A responsive ChatGPT-style AI chat app with a secure server-side Groq integration.

## Run locally

1. Install Node.js 18 or later.
2. Run `npm install`.
3. Set `GROQ_API_KEY` in your environment (never put it in browser code).
4. Optional: set `GROQ_MODEL` to a model available to your Groq account.
5. Run `npm start` and open `http://localhost:3000`.

The default model is `openai/gpt-oss-120b` through Groq. You can override it with the `GROQ_MODEL` environment variable if needed.

## Deploy to Render

Create a new Web Service from this repository. Render detects `render.yaml`; set `GROQ_API_KEY` in the service Environment settings. The app uses `PORT` supplied by Render. Do not commit API keys to GitHub.

## Features

- Responsive ChatGPT-inspired dark interface
- Chat composer with Enter-to-send and Shift+Enter newline
- Starter prompts and new/clear chat controls
- Groq-backed assistant through a server-side endpoint
- Friendly setup errors when the API key is missing
