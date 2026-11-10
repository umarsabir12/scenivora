# Costs and expenses

Last checked against OpenAI's pricing page: **2026-10-24**. Prices change, so re-check before
relying on these numbers. The app's price constants live in code and must match:

- `Ai::TextGenerator::PRICING_PER_MILLION` (text)
- `Ai::SpeechGenerator::PRICE_PER_MILLION_CHARACTERS` (speech)

## Short answer

- **One script (6 minutes):** about **$0.60** with research. Measured on "Prince Philip: the baby
  smuggled out of Greece in an orange box": Wikipedia research $0.48-0.51 (about 61k tokens), then
  `gpt-5.5` writing from it $0.06-0.10 (a second, shortening call adds about $0.05 when the first
  draft runs long). Rewrites with the same brief reuse the research. With
  the Director `off`, `gpt-4o-mini` writes from the brief alone for about **$0.0007**.
- **One voice-over (5 minutes, `tts-1`):** about **$0.07**. This is almost all of the cost of a video.
- **Running the test suite:** **$0**. Tests never call OpenAI.
- **Setting up all nine voice samples, once:** about **$0.005**. After that, playing them is free.

## Prices used

| Service                     | Model         | Price                          | Source                  |
| --------------------------- | ------------- | ------------------------------ | ----------------------- |
| Script (input)              | `gpt-4o-mini` | $0.15 per 1M input tokens      | OpenAI pricing page     |
| Script (output)             | `gpt-4o-mini` | $0.60 per 1M output tokens     | OpenAI pricing page     |
| Voice-over                  | `tts-1`       | $15.00 per 1M characters       | OpenAI pricing page     |
| Voice-over, higher quality  | `tts-1-hd`    | $30.00 per 1M characters       | OpenAI pricing page     |
| Voice-over (not used by default) | `gpt-4o-mini-tts` | $12.00 per 1M audio output tokens, $0.60 per 1M text input tokens | OpenAI pricing page |

The defaults are `gpt-4o-mini` for scripts and `tts-1` for voices. Override them with
`OPENAI_TEXT_MODEL` and `OPENAI_SPEECH_MODEL` in `.env`.

## Cost per video

Estimates assume 150 words per minute, about 0.75 words per token, about 6 characters per word
(including spaces), and about 400 input tokens for the script prompt.

| Video length | Words  | Script (text)  | Narration characters | Voice (`tts-1`) | Voice (`tts-1-hd`) |
| ------------ | ------ | -------------- | -------------------- | --------------- | ------------------ |
| 3 minutes    | 450    | ~$0.0004       | 2,700                | ~$0.041         | ~$0.081            |
| 5 minutes    | 750    | ~$0.0007       | 4,500                | ~$0.068         | ~$0.135            |
| 10 minutes   | 1,500  | ~$0.0013       | 9,000                | ~$0.135         | ~$0.270            |

**Each rewrite of a script costs the same as the first script.** Each voice regeneration costs
the same as the first voice. Voice samples are paid once per voice and then reused.

**Voice samples:** the sample sentence is 50 characters, so one sample costs about $0.00075 with
`tts-1`. The nine shipped samples were generated once for about $0.005 in total. Playing them is free:
they are static files in `public/voice_samples/`, so no request goes to OpenAI. Regenerate a sample
only if you change its text or voice list.

**Scene images:** searching Wikipedia, Wikimedia Commons and Pixabay, scoring the results and
filler footage are free. The paid parts are the scene plan, the picture check, the picture scout
and AI images; see **Checking pictures** and **AI scene images** below.

**Speed previews** are played in the browser, so they cost nothing. Only the final narration sends
the chosen speed to OpenAI.
**Budget guide:** at about $0.07 per 5-minute video, $5 of credit covers roughly 70 videos of that
length, or several hundred scripts with no voice-over.

## Checking pictures

- **Scene plan from research:** projects researched before their script (every Create video
  project) are planned by `gpt-4o-mini` from that research, under a cent. The Director's plan
  below is only used for projects without research.
- **Director (research and plan):** one call per project with `gpt-5.5` and OpenAI web search
  limited to Wikipedia. Measured $0.26 for 12 scenes (28k tokens, 3 searches, 67 s). Prices:
  $5 per 1M input tokens, $30 per 1M output tokens (reasoning counts as output), $10 per 1,000
  searches. Compared on the same project: `gpt-5-mini` $0.10, `gpt-4.1` $0.05, but neither planned
  as well (gpt-4.1 never named the key articles). Not used in "AI images for every scene" mode.
- **Scoring:** free. Candidates are scored in code (`Media::CandidateScore`) and only the best 4 per
  scene reach the picture check. It replaced a one-call relevance check (measured $0.0006 for 14
  scenes) and roughly halves the previews the picture check looks at.
- **Filler footage:** free. A fixed list of Commons clips (`config/fillers.yml`); no search or AI call.
- **Wikipedia article pictures:** free (no key, no AI); one request per article, up to about 18 per video.
- **Picture check:** one call per scene with up to 6 small previews (3 before October 2026), estimated
  $0.002 per scene, about double the 3-preview check ($0.001, about 6,400 tokens). About $0.05 for a
  5-minute video.
- **Picture scout:** a small `gpt-5-mini` search agent for each scene still without a picture
  (at most 10 per run), up to 6 model calls with low-detail previews. Estimated 1-2 cents a scene
  (to be measured), plus about $0.002 for the picture check of its choice. It replaced the Director's
  storyboard review (measured $0.05-0.16) and the second-chance query rewrite.
- **Measured on a 10-scene project (Panama Canal):** the whole fetch, including planner, relevance
  check, picture checks and second chance, cost $0.0145 and took about 3.5 minutes.

## AI scene images

- **Measured cost: $0.0127 per image** (`gpt-image-1-mini`, medium, 1536x1024; 4 images measured).
  A 5-minute video with every scene as AI costs about $0.38; with real photos first, typically
  10–20 suggested scenes, about $0.13–0.25.

- Model: `gpt-image-1-mini` (cheapest image model on OpenAI's pricing page, checked 2026-10-26):
  $2.00 per 1M text input tokens, $8.00 per 1M image output tokens. The page gives no per-image price.
- The app records each image's real cost from the token usage the API returns (`ApiUsage`, operation
  `ai_image`). No image has been generated yet, so there is no measured per-image cost.
- Users pay in app credits (`CREDITS_PER_AI_IMAGE`, placeholder 5). The dollar value of a credit is
  not decided.

## Music, render and publish

- **Music:** free. Tracks come from Wikimedia Commons, and uploads are your own.
- **Render:** free. ffmpeg runs on this machine. Large videos use local disk under `storage/`.
- **Captions (SRT):** free. Timings come from measuring the narration parts.
- **YouTube details:** one text-model call per **Write details** click, about $0.0005 for a
  5-minute script with `gpt-4o-mini` (estimate; recorded in `ApiUsage` as `metadata`).

## Single tools (sidebar: Create)

- **Text to speech:** OpenAI `tts-1`, $15 per 1M characters, so the 10,000-character maximum costs
  about $0.15 and a 1,000-character text about $0.015. Recorded in `ApiUsage` as `create_speech`
  against the creation. Users pay 1 credit per started 1,000 characters (placeholder, set in
  `config/creation_models.yml`). Measured 2026-11-11: 161 characters cost $0.0024 (matches the
  rate), 9.9 s of audio, 24 kHz mono MP3 at -24.5 LUFS (quiet; not normalised yet).
- **Create video, Create image, Write text:** no models yet, so no cost.

## Free items

- Test suite (`bin/rails test`): mocked, no network calls, no cost.
- PostgreSQL, plus Solid Queue and Solid Cache (stored in PostgreSQL, so no Redis): run locally, no cost.
- ffmpeg and ffprobe: free and open source, installed locally.
- Rails, Devise, Tailwind and the other gems: free.

## Cost controls

1. **Set a monthly usage limit** on the OpenAI dashboard (**Settings → Limits**). This is the
   hard stop, and it protects you from a bug that loops.
2. **Keep the default `tts-1`** unless a sample sounds clearly worse. `tts-1-hd` costs twice as much.
3. **Do not run live tests in a loop.** Use one short script and one short voice sentence to check
   connectivity. That costs under $0.10 in total.
4. **Use the tests for development.** They never call OpenAI and cost nothing.
5. **Check actual usage.** The app records every paid call in the `api_usages` table. In a Rails
   console, `ApiUsage.group(:operation).sum(:cost_usd)` shows the totals by operation. These totals
   are estimates from our price constants. The OpenAI dashboard shows the real bill.

## Expense log

Record real charges here as you incur them. Use the OpenAI dashboard for the amounts.

| Date       | Item                              | Amount (USD) | Notes                          |
| ---------- | --------------------------------- | ------------ | ------------------------------ |
| 2026-10-24 | Cost estimates written            | $0.00        | No API calls made              |
| 2026-10-24 | Test script generation (project 4) | $0.00        | Rejected with HTTP 429: no API credit. Retry after adding credits. |
| 2026-10-24 | Two test script generations       | $0.00052     | Versions 1 and 2 of project 4 (estimate from our price constants) |
| 2026-10-24 | Voice sample files (9 voices)     | $0.00525     | One-time generation, saved to public/voice_samples |
| 2026-10-26 | Scene image search (Commons, Pixabay) | $0.00 | Free sources, no paid API calls |
| 2026-10-24 | Voice name check (rejected calls, one 1-character call) | $0.00002 | Confirmed tts-1's accepted voice names |
| 2026-11-11 | Text to speech tool, live check (1 `tts-1` call, 161 characters) | $0.0024 | Confirmed the credit charge, recorded cost and MP3 output |
|            |                                   |              |                                |

## Revision history

- 2026-10-24: first version. Prices checked against OpenAI's pricing page.
