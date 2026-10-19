# Devora AI — automatic long-video worker

This background worker is designed to turn a user prompt into a 1–60 minute MP4. Scene planning is done server-side with Groq; scene prompts are stored in the private project row and are not displayed in the app. Seedance 2.5 generates 15-second clips, then FFmpeg assembles them and the worker uploads a private MP4 to Supabase Storage.

## Deploy

1. In Render, create a Blueprint from this repository; it reads the root `render.yaml`.
2. Set only `SUPABASE_SERVICE_ROLE_KEY` as a Render secret (along with the Supabase URL configured in `render.yaml`). Keep `KIE_API_KEY` and `GROQ_API_KEY` in Supabase Edge Function Secrets; the worker now calls the private `devora-worker-provider` Edge Function for scene planning and KIE task creation/status. Never put provider keys in Flutter or GitHub source.
3. Confirm the `devora_long_video_projects` table exists in Supabase (it was created for this project).
4. Wait for the worker service to show healthy in logs. The worker exposes `/health` for service checks.
5. Rebuild the Android APK through GitHub Actions after deployment.

## Important cost and operational notes

- The UI asks for explicit confirmation before queuing a project and displays the estimate.
- Configured Seedance estimate: 480p 28 credits/sec, 720p 63 credits/sec, 1080p 158 credits/sec. A full hour at 720p is 226,800 credits; a full hour at 1080p is 568,800 credits. Verify live KIE pricing and account balance before confirming.
- This worker processes one project at a time and clips sequentially. A 1-hour project means up to 240 clips. Generation may take hours and consumes KIE credits for each successful provider task.
- It does not use Devora's in-app credit wallet for this project; KIE charges the connected KIE account directly. Do not submit until the KIE account has enough credits.
- Long-running jobs need a persistent worker process. Do not deploy this as a serverless/edge function.
- The final MP4 is uploaded to a private Storage bucket and the signed download link expires after seven days. Provider credentials are read by Supabase Edge Functions; the Render worker does not need KIE or Groq keys.
