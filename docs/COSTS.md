# Costs and expenses

Last checked against OpenAI's pricing page: **2026-10-24**. Prices change, so re-check before
relying on these numbers. The app's price constants live in code and must match:

- `Ai::TextGenerator::PRICING_PER_MILLION` (text)
- `Ai::SpeechGenerator::PRICE_PER_MILLION_CHARACTERS` (speech)

## Short answer

- **One script (5 minutes):** about **$0.0007**, under a tenth of a cent.
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

**Scene images** cost nothing today. Wikimedia Commons and Pixabay are free to search, and the app
doesn't call any paid service to find images. Two costs come later:
- A vision check on each candidate image, not built yet. Its estimate will go on the Create scene
  button once its price is confirmed.
- AI-generated images, if enabled, cost per image. Not built yet.

**Speed previews** are played in the browser, so they cost nothing. Only the final narration sends
the chosen speed to OpenAI.
**Budget guide:** at about $0.07 per 5-minute video, $5 of credit covers roughly 70 videos of that
length, or several hundred scripts with no voice-over.

## AI scene images

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
|            |                                   |              |                                |

## Revision history

- 2026-10-24: first version. Prices checked against OpenAI's pricing page.
