# Scenivora

A Rails 8 app that makes faceless YouTube videos. A user gives a topic (plus optional instructions,
category and target length); the app researches it, writes a script, builds a storyboard with free
pictures and AI images where needed, generates narration and music, and renders the video.

## Standing rules

- **Own the result: a video people watch to the end.** Green tests are the minimum. After a change
  that affects a video, check the real output (render a frame, measure the audio with
  `ffmpeg ... ebur128`/`astats`, read the script) before calling it done. Find the cause, not the
  symptom.
- **Research before building.** For a new provider or model, read its own docs and pricing first,
  write down the confirmed facts (price, limits, field names, license), mark what's unconfirmed, then
  make one free or tiny call to confirm the request shape before writing the service.
- **Recommend, don't survey.** A short table of options, then the one you'd pick and why. Say
  plainly when something is wrong, including your own earlier work.
- **Every paid API call needs the user's yes first:** what it is, how many calls, the cost in
  dollars. Free calls (local ffmpeg, free models) don't, but say you're making them.
- **Budget: about $1 a day and $0.50 a run.** Research well under $0.40, a script under $0.10. This
  replaces the older "$2–3 per video" target; when unsure, ask. Record every cost in `ApiUsage` and
  measured numbers in `docs/COSTS.md`.
- **Never delete projects, scenes, uploads, AI images or blobs** without the user's explicit yes for
  that exact delete ("let go of the old projects" is not one). Test on fresh projects or copies, never
  the one the user is working on. Look before overwriting a file or blob.
- **Shared repo.** Other Claude sessions work here too. Never edit, stage, revert or commit another
  session's uncommitted files; check `git status` first. Commit only your own files, by explicit
  path (`git commit --only <path> <path>`; zsh doesn't word-split variables, so write paths out).
- **Ask before adding a gem.** Don't add one without checking first.
- **Keep docs updated.** `README.md` documents the app and its flow; `docs/COSTS.md` documents
  pricing and measured costs. Update both when a change affects what they describe.
- **Keep videos production-ready**, not just passing tests — judge real output, not just green CI.
- **Test AI-touching code cheaply before relying on it.** Run the script against sample input and
  read the actual output, rather than assuming it works from the code alone. Prefer this over
  burning API credit on a full end-to-end run.
- **API keys live in `.env` only.** Never print, paste, log or commit a key, even partially. To
  check one exists, print only its length: `awk -F= '/^DEEPINFRA_API_KEY/{print length($2)}' .env`.
- **Commit author is umar sabir** (not an AI identity) unless told otherwise.
- **Don't push or deploy unless asked.**
- **Before a destructive git command** (`checkout`/`restore`/`reset`/`clean`, `rm -rf` in the repo),
  check `git status` first and stash or commit anything uncommitted.

## Channel content rules

The channels are Great Men Stories and Daily Body Repair.

- Facts need 2+ independent sources. Never invent a quote, number or scene.
- Islamic history: **never show the faces of the Prophet ﷺ or the Sahaba**, in any medium (the
  `no_face` / `no_figure` depiction rules).
- AI images and clips: people only from behind or in silhouette; no real faces, text, logos or
  made-up scoreboards.
- The user uploads, as private or scheduled, with "Made with AI" set to No. Realistic AI video
  footage may need Yes under YouTube's rules, so raise it before AI clips go into a video.

## Running things

- `bin/dev` — Rails server + asset watchers.
- `bin/jobs` — Solid Queue worker. **Restart it after any job/service code change** — it keeps
  running old code otherwise, which has caused confusing bugs before.
- `bin/rails test` — full suite, no network calls, no cost. Run before considering work done.
- `bin/rubocop` — lint; keep it clean.
- Scratchpad scripts (trying a service against real data, offline experiments) go in the session's
  scratchpad directory, not in the repo.

Things that bite:

- **Puma and the worker are usually running** (localhost:3000) and the user may click buttons while
  your script runs (a "Generate voice" click mid-render once replaced the voice blob). Check what's
  queued before starting a job, and say when you're about to run one.
- **commons.wikimedia.org is blocked by the user's ISP.** api.wikimedia.org, en.wikipedia.org,
  upload.wikimedia.org and Wikidata work; use `/thumb/.../330px-` URLs for previews.
- The local **ffmpeg has no libass and no drawtext**: no burned-in captions or text.
- **The Desktop is iCloud-synced.** Offloaded ("dataless") files make reads hang; check with
  `find <dir> -flags +dataless`.
- There's no `timeout` command on this Mac.
- Don't promise a voice the app doesn't have; the list is `Ai::SpeechGenerator::VOICES`.

## Architecture

- **Flow:** `ProduceVideoJob` runs research → script → storyboard → pictures → AI images for
  whatever's left. The storyboard page (`scenes/show.html.erb`) is the main editing surface — no
  separate script-edit page. From there: Voice → Render (music is picked here) → Publish.
- **AI services** live under `app/services/ai/`, one class per job (`ResearchGenerator`,
  `ScenePlanner`, `ImageVerifier`, `PictureScout`, `TextGenerator`, `SpeechGenerator`,
  `ImageGenerator`). Each records its real cost to `ApiUsage` (`provider`, `operation`, `cost_usd`).
  `Ai::Error` is the common error class; `Ai::OutOfCredits` (provider account out of credit, not the
  user's credits) stops the run instead of continuing with unchecked output.
- **Picture pipeline** (`FindSceneImagesJob`): plans search terms per scene, builds a shared
  per-video picture library from Wikipedia/Commons, scores candidates in code
  (`Media::CandidateScore`, no AI call) and only sends the best few to the paid picture check.
  Scenes with no fitting picture get filler footage (`Media::Fillers`, `config/fillers.yml`) or an
  AI image, depending on whether the scene is a mood shot or needs a specific subject.
- **Credits/pricing** constants (`CreditPricing`) are placeholders — pricing isn't finalized yet.

## Workflow preferences

- For a UI/feature request, batch related small changes into one pass rather than one round trip
  per tweak.
- When something seems off in a request ("auto swap" when nothing auto-swaps), say so and explain,
  rather than silently complying or silently ignoring it.
- Read only the file sections you're about to change, not whole large files, when the content is
  already known from context.
- New Rails model/view/service: look at an existing similar one first and match its style
  (comment density, naming, structure) rather than imposing a generic pattern.
