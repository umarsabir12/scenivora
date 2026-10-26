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

## Later steps

- [ ] Step 4: background music.
- [ ] Step 5: render MP4.
- [ ] Step 6: title, description, tags, publish.
- [ ] Production setup: storage, database password, deployment.
