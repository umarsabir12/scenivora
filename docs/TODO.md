# TODO

Work deferred from the current plan. Update this file as items are finished or decided.

## Scenes and images (step 3)

Done
- [x] **Scene planner (v1).** `Ai::ScenePlanner` makes one JSON call per run and maps queries and
      flags onto each scene. Built and tested with fakes. **Not yet run against OpenAI.** The first
      live run needs your approval (about $0.0004 for a 3-minute script).
- [x] Commons search uses the planner's first query. Keyword queries remain as the fallback.

Next up
- [x] First live planner run (project 4, 3 runs in total, about $0.0016 across them).
- [x] Commons search moved to the reachable Wikimedia endpoints, with license filtering and 429 backoff.
- [ ] Planner queries for generic scenes are weak (e.g. "connected world technology" returned unrelated
      photos). Tune the planner prompt, or ask it for more specific queries.
- [ ] Scenes with no free image (for example "Nikola Tesla grave") need the AI fallback or manual upload.
- [ ] Credit text is inconsistent ("Unknown author", "Wikimedia Commons contributor"). Decide how to show it.

Deferred
- [ ] **Pixabay images.** Needs `PIXABAY_API_KEY` in `.env`. Skipped for now.
- [ ] **Vision verification of candidates.** Off for v1. Blocked until current vision-model
      pricing is checked. About 120 calls per video if enabled.
- [x] **AI image generation** (swap panel tab, charged in credits, refunded on failure). Built and tested
      with fakes. **No live image has been generated yet.**
- [ ] First live AI image: measure the real per-image cost, then set the credit price from it.
- [ ] Decide credit pricing: dollars per credit, credits per AI image, starting credits for new users.
- [ ] Credit purchase flow (none yet; credits are granted with `bin/rails credits:grant`).
- [ ] Show credit history to users (the `credit_transactions` table already records it).
- [ ] **Video clips (not fetched yet).** Scenes use still images only for now. Later:
      search Commons for video (`filetype:video` on the search endpoint, then `prop=videoinfo` for the
      URL and license), add Pixabay videos once that source is enabled, decide how a clip fits an
      8–12 s scene (trim, loop, or slow down), show video candidates in the swap panel, and handle
      clips in the render step.
- [ ] **Aspect ratio.** Decide whether v1 targets 16:9, 9:16, or both.
- [ ] **Credit price.** Decide what one credit costs in dollars before showing credits instead of dollars.
- [x] **Upload your own image** for a scene.
- [x] **Approve scenes** action that moves the project to `scenes_ready` (requires an image on every scene).
- [ ] Drag to reorder scenes: left out on purpose, because scenes follow the narration's timing. Revisit if scenes ever become independent of narration.
- [ ] Pexels as an image source (shown in the mockup, not planned yet).

## Voice

- [ ] Verify the TTS input limit (4,096 characters) against OpenAI's current docs.
      The docs page was not reachable when this was written.
- [ ] Recover a voice track stuck in `processing` after a worker crash (timeout or cleanup job).
- [ ] `gpt-4o-mini-tts` voices (ballad, cedar, marin, verse). Blocked: the model is marked
      deprecated and has no published per-minute price.

## Costs and billing

- [ ] Record voice-sample generation in `ApiUsage` (samples have no project today).
- [ ] Confirm current prices for `gpt-4o-mini` and `tts-1` against OpenAI's pricing page.

## Platform

- [x] Ruby 3.2.2 to 3.4.12 (`.ruby-version`, Dockerfile). Tests clean with deprecation warnings on.
- [ ] Rails 8.0 to 8.1 before 2026-11-07, when 8.0 support ends.
- [ ] Ruby 4.0 after Rails 8.1 (4.0 moves more standard libraries into separate gems).

## Later steps

- [x] Step 4: background music (Commons library or upload, volume).
- [x] Step 5: render MP4 (1080p, local ffmpeg, thumbnail).
- [x] Step 6: AI title, description, tags and category, with a credits footer; downloads.
- [ ] One-click YouTube upload (needs Google OAuth and the YouTube Data API; a Google Cloud project and keys).
- [ ] Analytics dashboard.
- [x] Captions step 1: paragraph-timed narration and an SRT download for YouTube.
- [x] Captions step 2: burned-in captions (1–3 words, yellow numbers and names, hook title, dark band)
      via an ASS file, using Homebrew's ffmpeg-full and the bundled Anton font.
- [ ] Soften the top edge of the caption band (a gradient instead of a hard edge).
- [ ] Caption keywords from the planner, not just numbers and capitalised words.
- [ ] Hook text from the planner, so the first render has a hook (today it uses the YouTube title,
      which exists only after **Write details**).
- [x] Fixed the plain Homebrew `ffmpeg` on this machine (`brew upgrade ffmpeg` to 9.0.2).
- [ ] Captions option A: word-accurate timings from transcription (Whisper, $0.006/minute on
      OpenAI's pricing page, checked 2026-10-27). Confirm word timestamps are still returned before building.
- [ ] Upload the SRT as a YouTube caption track automatically (needs the youtube.force-ssl OAuth scope).
- [x] Render polish: image fit with blurred background, Ken Burns zoom alternating in and out, music
      ducked under the voice, loudness -14 LUFS, vignette.
- [ ] Mark a render as out of date when scenes, music or narration change after it.
- [ ] Recover a project stuck in `rendering` after a worker crash.
- [ ] Decide whether rendering and YouTube details charge credits (both currently free to the user).
- [ ] File expiry for rendered videos (the mockup shows "expires in 7 days").
- [ ] Music library page in the sidebar (currently "Soon").
- [ ] Production setup: storage, database password, deployment.
