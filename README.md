# Devora AI — Native Flutter APK

This is an Android Flutter app, not a website frontend. It includes Supabase email/password sign-in, AI chat via the existing destiny-ai Edge Function, image/video/music generation via devora-media, model and resolution choices, approximate credit display, and generation status polling.

## Get the APK
1. Open the Actions tab.
2. Run “Build Devora AI APK” (or push a change to main).
3. Download the devora-ai-release-apk artifact from a successful run.
4. Extract the ZIP and install app-release.apk on Android.

## Backend requirements
The Supabase project and its destiny-ai and devora-media Edge Functions must remain active. KIE and Groq secrets must stay in Supabase secrets, never in the APK. Generation relies on the current Supabase database RPCs and policies. The APK is not signed with a Play Store release key.
