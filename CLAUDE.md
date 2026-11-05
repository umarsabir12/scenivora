# Scenivora

A Rails 8 app that makes faceless YouTube videos. A user gives a topic (plus optional instructions,
category and target length); the app researches it, writes a script, builds a storyboard with free
pictures and AI images where needed, generates narration and music, and renders the video.

## Standing rules

- **Never compromise quality to save a few cents.** The target price is $2–3 credit per video; the
  budget should be set from that, not the other way round.
- **Ask before adding a gem.** Don't add one without checking first.
- **Keep docs updated.** `README.md` documents the app and its flow; `docs/COSTS.md` documents
  pricing and measured costs. Update both when a change affects what they describe.
- **Keep videos production-ready**, not just passing tests — judge real output, not just green CI.
- **Test AI-touching code cheaply before relying on it.** Run the script against sample input and
  read the actual output, rather than assuming it works from the code alone. Prefer this over
  burning API credit on a full end-to-end run.
- **API keys live in `.env` only.** Never paste or commit a real key, even partially.
- **Commit author is umar sabir** (not an AI identity) unless told otherwise.
- **Don't push or deploy unless asked.**
- **Before a destructive git command** (`checkout`/`restore`/`reset`/`clean`, `rm -rf` in the repo),
  check `git status` first and stash or commit anything uncommitted.

## Running things

- `bin/dev` — Rails server + asset watchers.
- `bin/jobs` — Solid Queue worker. **Restart it after any job/service code change** — it keeps
  running old code otherwise, which has caused confusing bugs before.
- `bin/rails test` — full suite, no network calls, no cost. Run before considering work done.
- `bin/rubocop` — lint; keep it clean.
- Scratchpad scripts (trying a service against real data, offline experiments) go in the session's
  scratchpad directory, not in the repo.

## Architecture

- **Flow:** `ProduceVideoJob` runs research → script → storyboard → pictures → AI images for
  whatever's left. The storyboard page (`scenes/show.html.erb`) is the main editing surface — no
  separate script-edit page. From there: Voice → Music → Render → Publish.
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
