# Roadmap to production

Status as of 2026-10-28 (items 1.1–1.5 done). Pricing is deliberately left for a later phase.
Smaller open items live in [TODO.md](TODO.md); costs in [COSTS.md](COSTS.md).

## Phase 1: Video quality (in progress)

| # | Task | Why it matters | State |
| - | ---- | -------------- | ----- |
| 1.1 | Fit every image to the frame: fill when the shape is close to 16:9, otherwise show the whole image over a blurred copy of itself | Portraits and odd shapes were cropped badly | Done |
| 1.2 | Slow zoom (Ken Burns), alternating in and out per scene | Still images feel static without motion | Done |
| 1.3 | Burned-in captions: 1–3 words, keywords and numbers in yellow, dark band behind | Many viewers watch without sound; captions hold attention | Done |
| 1.4 | Music ducked under the voice, final loudness −14 LUFS | Clear voice, consistent volume on YouTube | Done |
| 1.5 | SRT caption file for YouTube | Accessibility and search | Done |
| 1.6 | Scene cuts on real sentence timing (from paragraph timings) | Images change when the sentence changes | Not started |
| 1.7 | Shorter scenes option (4–6 s) for faster pacing | Retention drops when a visual stays on screen too long | Not started |
| 1.8 | Hook title over the first seconds | Gives the first frame a reason to keep watching | Not started (needs hook text from the planner) |
| 1.9 | Vertical 9:16 format (Shorts) | Shorts reach a separate audience | Not started |
| 1.10 | Video clips for action scenes | Motion footage beats stills for travel, crowds, weather | v1 done (Commons archival video for hook and action scenes) |
| 1.11 | Transitions and sound effects (short whoosh, fade) | Pattern interrupts keep attention | Not started |

## Phase 2: Content quality

| # | Task | State |
| - | ---- | ----- |
| 2.1 | Sharper planner queries for generic scenes (they returned unrelated photos) | Not started |
| 2.2 | Vision check of image candidates (relevance, watermarks, text, wrong person) | Not started, needs pricing check |
| 2.3 | Hook and keyword output from the planner (for the hook title and caption highlights) | Not started |
| 2.4 | Script length accuracy: hit the target minutes within ±10% | Not started |
| 2.5 | AI thumbnail with title text | Not started |

## Phase 3: Reliability

| # | Task | State |
| - | ---- | ----- |
| 3.1 | Recover jobs stuck in `processing` or `rendering` after a worker crash (timeout + cleanup job) | Not started |
| 3.2 | Retry network failures (Wikimedia, OpenAI) with backoff, without paying twice | Partly (429 backoff, planner idempotent) |
| 3.3 | Separate `render` queue with a concurrency limit, so renders don't block scripts and voices | Not started |
| 3.4 | Restart workers on deploy (avoid stale-schema failures seen in development) | Not started |
| 3.5 | Clean up old renders and temporary files; file expiry for videos | Not started |
| 3.6 | Browser (system) tests for the full flow; CI runs a real ffmpeg render | Not started |

## Phase 4: Production infrastructure

| # | Task | State |
| - | ---- | ----- |
| 4.1 | Upgrade Ruby (3.2 was end of life) and Rails (8.0 support ends 2026-11-07) | Done: Ruby 3.4.12 and Rails 8.1.4 with 8.1 defaults (2026-10-28). Ruby 4.0 later |
| 4.2 | Deploy (Docker image with ffmpeg + libass and the bundled fonts; Kamal or a PaaS) | Not started |
| 4.3 | Object storage for videos and audio (S3 or Cloudflare R2) instead of local disk | Not started |
| 4.4 | Production PostgreSQL, backups | Not started |
| 4.5 | Real email delivery (password resets) | Not started |
| 4.6 | Secrets in Rails credentials or the host's secret store; key rotation | Not started |
| 4.7 | Error tracking, structured logs, uptime and queue monitoring | Not started |
| 4.8 | Domain, HTTPS | Not started |

## Phase 5: Safety, legal and accounts

| # | Task | State |
| - | ---- | ----- |
| 5.1 | Per-user spending limits and rate limits on every paid action | Partly (AI images use credits) |
| 5.2 | Moderate user prompts before paid generation | Not started |
| 5.3 | License and credit accuracy for every asset in the description | Done for Commons images and music |
| 5.4 | AI disclosure: YouTube's "altered or synthetic content" setting, guidance in the Publish step | Not started |
| 5.5 | Terms of service, privacy policy, cookie notice | Not started |
| 5.6 | Admin view: users, usage, failed jobs | Not started |

## Phase 6: Growth (after launch)

- Pricing, credit packs and payments (deferred on purpose).
- One-click YouTube upload with captions (Google OAuth, YouTube Data API).
- Analytics dashboard.
- Music library page, saved voices and styles per channel.

---

# What makes a faceless video interesting

These are the basics the pipeline should get right, roughly in order of impact.

1. **The hook (first 5–15 seconds).** Open with the most surprising fact, a question, or the end of
   the story. Pair it with the strongest image and, ideally, a short hook title on screen. Most
   viewers decide here whether to stay.
2. **Pacing: change the picture often.** A new visual every 4–6 seconds keeps attention; a single
   image held for 10+ seconds feels slow. Cut on sentence boundaries so the picture changes with
   the words.
3. **Motion on every still.** A slow zoom or pan (Ken Burns), alternating direction, makes photos
   feel like footage. Keep it subtle (5–10% over the scene).
4. **Pictures that match the words.** When the narration names a person, place or date, show it.
   Real photos for real people; AI images only for scenes nothing real can show.
5. **Captions on screen.** Large, bold, 1–3 words at a time, centred low, with key words in a
   highlight colour. They help viewers watching on mute and those who skim.
6. **Clean audio.** The voice must be clear and steady. Music sits well under it (ducked while
   speaking) and fades at the end. Normalise the final mix to about −14 LUFS for YouTube.
7. **Story shape.** Setup, rising tension, a turning point about halfway, then a payoff. Leave a
   question open early ("but that wasn't the strangest part") and answer it later.
8. **Pattern interrupts.** Every 30–60 seconds, change something: a zoom direction, a map, a
   close-up, a short silence, a sound effect. Sameness loses viewers.
9. **Title and thumbnail.** A curiosity-driven title that the video actually answers; a thumbnail
   with one clear subject, high contrast and 2–4 words of text.
10. **Honest labels and credits.** Disclose AI narration and AI images, credit every licensed asset.
    It protects the channel.
