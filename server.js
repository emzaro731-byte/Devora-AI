// Compatibility entry point for Render services configured with "node server.js".
// The production worker implementation lives in long-video-worker/server.js.
// Prefer the Docker Background Worker defined in render.yaml because it includes FFmpeg.
require('./long-video-worker/server.js');
