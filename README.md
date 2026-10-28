# Scenivora

AI video creation for faceless YouTube creators. A creator describes a video, reviews an
AI-written narration script, generates an AI voice-over, and (in later steps) adds scenes,
music and a rendered MP4. The creator uploads the video to YouTube themselves.

## Status

| Step | Area                                   | State        |
| ---- | -------------------------------------- | ------------ |
| 1    | Auth, layout, projects, script         | Done         |
| 2    | Voice generation                       | Done         |
| 3    | Scenes and images                      | Done (planner, Commons, review, upload, AI images) |
| 4    | Background music                       | Done (Commons library or upload, volume) |
| 5    | Render MP4                             | Done (1080p, local ffmpeg)  |
| 6    | Title, description, tags, publish      | Done (AI details, credits footer, downloads) |

All six wizard steps work. One-click YouTube upload and analytics come later (see `docs/TODO.md`).

## Requirements

- Ruby 3.4.12 (see `.ruby-version`; with rbenv: `rbenv install 3.4.12`)
- PostgreSQL running locally (developed against 15), with a role that can create databases
- ffmpeg with libass (for captions), H.264 and AAC: `brew install ffmpeg-full`. It installs next to
  any existing ffmpeg (keg-only) and the app finds it automatically at
  `/opt/homebrew/opt/ffmpeg-full/bin`. Set `FFMPEG_BIN` / `FFPROBE_BIN` to use another build. The plain
  `brew install ffmpeg` works too, but renders then skip burned-in captions.
- An OpenAI API key with billing enabled (see below)

## Getting an OpenAI API key

The app calls OpenAI for two things: writing scripts (text model) and narrating them (speech model).
Without a key, both features fail with a clear message in the UI. Everything else still works.

1. Create or sign in to an account at https://platform.openai.com.
2. Turn on billing: open **Settings → Billing**, add a payment method, and add credits.
   Requests fail with a quota error when the balance is empty.
3. Optional but recommended: set a monthly **usage limit** under **Settings → Limits**
   so a bug or a runaway loop cannot spend more than you expect.
4. Open **API keys** (https://platform.openai.com/api-keys) and choose **Create new secret key**.
   Copy it immediately. OpenAI shows it only once.
5. Put it in your local `.env` file (see **Setup**, step 3). `.env` is git-ignored, so the key
   stays on your machine. Do not paste the key into chats, issues or screenshots. If a key
   leaks, revoke it on the same API keys page and create a new one.

Cost estimates shown in the app come from the prices in the code (see **Pricing** below).
Check your OpenAI usage dashboard for the real charges.

## Setup

```sh
# 1. Install gems
bundle install

# 2. Create and migrate the databases (primary, queue, cache, cable)
bin/rails db:prepare

# 3. Create your local settings file and add your OpenAI key (see above)
cp .env.example .env
#    then edit .env and set OPENAI_API_KEY=sk-...

# 4. Create the development test user (test@example.com / password123)
bin/rails db:seed

# 5. Start the web server, the Solid Queue worker and the Tailwind watcher
bin/dev
```

Open http://localhost:3000 and sign in with `test@example.com` / `password123`, or sign up
with your own address. Then create a project, click **Generate script**, and once the script
is ready open the **Voice** step.

If port 3000 is taken, run `PORT=3100 bin/dev`.

### Keys and accounts

| Service           | Key needed            | Used for                                      |
| ----------------- | --------------------- | --------------------------------------------- |
| OpenAI            | `OPENAI_API_KEY`      | Scripts, voices, scene planner, AI images, YouTube details |
| Wikimedia Commons | None                  | Scene images and background music             |
| Pixabay           | `PIXABAY_API_KEY`     | Optional, currently skipped                   |
| ffmpeg            | None (local install)  | Joining narration, rendering the MP4          |

Only `OPENAI_API_KEY` is required. Everything else in the pipeline is free.

### Environment variables

Development and test read these from `.env` (loaded by `dotenv-rails`). Production reads them
from the real environment. `.env.example` lists every setting.

| Variable             | Required | Default       | Purpose                                              |
| -------------------- | -------- | ------------- | ---------------------------------------------------- |
| `OPENAI_API_KEY`     | Yes, for AI features | none   | Authenticates every OpenAI request                   |
| `OPENAI_TEXT_MODEL`  | No       | `gpt-4o-mini` | Model used to write scripts                          |
| `OPENAI_SPEECH_MODEL`| No       | `tts-1`       | Model used for narration and voice samples           |
| `OPENAI_IMAGE_MODEL` | No       | `gpt-image-1-mini` | Model used for AI scene images                  |
| `CREDITS_PER_AI_IMAGE` | No     | `5` (placeholder) | Credits charged per AI image                     |
| `FFMPEG_BIN`, `FFPROBE_BIN` | No | ffmpeg-full if installed, else `ffmpeg`/`ffprobe` on PATH | Which ffmpeg build to use |
| `PORT`               | No       | `3000`        | Port for `bin/dev`                                   |
| `PIXABAY_API_KEY`    | No       | none          | Enables Pixabay in scene image search (free account) |

Production also needs `SCENIVORA_DATABASE_PASSWORD` (see `config/database.yml`).

`.env` holds secrets and is git-ignored. Only `.env.example` (no values) is committed.
Changes to `.env` take effect when `bin/dev` is restarted.

### Processes

`bin/dev` runs three processes from `Procfile.dev`:

| Process | Command                       | Purpose                                 |
| ------- | ----------------------------- | --------------------------------------- |
| web     | `bin/rails server`            | The app                                 |
| jobs    | `bin/jobs`                    | Solid Queue worker (scripts and voices) |
| css     | `bin/rails tailwindcss:watch` | Rebuilds Tailwind CSS on change         |

Scripts, voices, scene images, music downloads, renders and YouTube details run in background jobs. If the `jobs` process is not running,
the page shows "Generating..." or "Starting..." until it starts.

## Using the app

1. **Sign up or sign in.** Password reset emails are not sent through a mail service in
   development. Open `log/development.log` and copy the reset link from the email.
2. **Dashboard.** Type a brief in "What's your next video about?", pick a tone and length,
   and click **Write script**. That creates the project and starts the script. Filter the list
   with All, In progress or Rendered.
3. **Project page.** The left column holds the script. Edit it freely: changes autosave.
   **Rewrite** creates a new version and keeps the old ones under "Previous versions".
4. **Voice tab.** Click **Go to Voice** on the project page. The tab has two parts:
   - **Generated voice** (top): the current narration with its duration and voice name, plus
     **Regenerate** and **Confirm voice**. Confirming locks in the voice and opens the Scenes step. If the script changes
     afterwards, the tab asks you to regenerate before you can confirm. Regenerating clears the
     confirmation.
   - **Narration voice** (below): pick a voice from the grid, play its sample, set the speed
     from 0.85x to 1.15x, check the estimated cost, and click **Generate voice**. Generation
     runs in the background, and progress updates live ("Generating part 2 of 4..."). The Voice
     tab reloads when it finishes. A failed run shows the error with **Retry**, and the previous
     narration is kept.
5. **Scenes.** Click **Create scene**: the narration is split into ~10-second scenes, the planner
   picks search terms, and free images are found on Wikimedia Commons. Review each scene, swap,
   upload or generate an AI image (for credits), then **Approve scenes & continue**.
6. **Music.** Pick a free track from the music library (Wikimedia Commons), or upload your own,
   and set its volume (default 18%, up to 50%). Music is optional: **Continue without music**
   skips it.
7. **Render.** Choose whether to burn captions in (on by default), then click **Render video**. The
   MP4 (1920x1080, H.264, AAC, −14 LUFS) is built on this machine with ffmpeg, with progress shown
   live. A failed re-render keeps the previous video.
8. **Publish.** Watch the video, download the MP4 and thumbnail, and click **Write details** for an
   AI title, description, tags and category. Edit them, **Save details**, then **Copy all details**
   and upload to YouTube yourself. **Download captions (.srt)** gives a caption file to upload in
   YouTube Studio under Subtitles.

The app uses a dark theme only. Colors are set in `app/helpers/application_helper.rb` (form
fields and buttons) and in the views.

## Tests and checks

```sh
bin/rails test        # 240 tests: models, services, jobs, controllers, auth flows
bin/rubocop           # style (rubocop-rails-omakase)
bin/brakeman          # security scan
bin/ci                # all of the above, plus setup, importmap audit and seeds (Rails 8.1 local CI)
```

The tests never call OpenAI, Wikimedia or ffmpeg, so they need no API key, network or ffmpeg:
the providers, downloads and ffmpeg are replaced with fakes.

## How it works

### Data model

- `User`: Devise account, `credits_balance` (placeholder, shown in the top bar).
- `Project`: brief (`prompt`), `tone`, `target_length_minutes`, `status`
  (`draft → script_ready → voice_ready → scenes_ready → media_ready → rendering → rendered`),
  and `settings` (JSON). `settings["script_generating"]` is true while a script is being
  written. `settings["ai_voice"]` is true after narration is generated, so the description can
  say "Narration is AI-generated".
- `Script`: versioned narration text. Autosave edits the latest version in place. Rewrite adds
  a new version.
- `AudioTrack`: the voice track for a project (`kind: voice`). Holds the voice name, speed,
  status (`pending → processing → ready | failed`), duration, the error message, the MP3
  attachment (Active Storage), `script_digest` (the fingerprint of the script it was made from), and
  `timings` (each narration part's text, start and end, for captions).
- `VoiceSample`: one cached sample per voice name, used by the voice picker.
- `AudioTrack` (`kind: music`): the background music track: title, credit, license, source,
  volume (0–50%), duration and the audio file.
- `Scene` / `SceneImage`: timed scenes, their planner output (`plan`), and image candidates
  (Commons links, uploads, or AI images in Active Storage), one of them selected.
- `Project` also holds the rendered `video` and `thumbnail` (Active Storage), `render_error`, and
  the YouTube details (`yt_title`, `yt_description`, `yt_tags`, `yt_category`).
- `CreditTransaction`: every change to a user's credit balance.
- `ApiUsage`: one row per paid API call batch (provider, operation, units, estimated cost).
  Operations: `script`, `voice`, `scene_plan`, `ai_image`, `metadata`.

### Script generation

`ScriptsController#create` marks the project as generating and enqueues `GenerateScriptJob`.
The job calls `Ai::TextGenerator` with a fixed system prompt (hook in the first 15 seconds,
story structure with a turning point, about 150 words per minute, plain narration only), saves
the next `Script` version, records an `ApiUsage` row, and broadcasts the result over Turbo Streams.

### Scene images (step 3)

`FindSceneImagesJob` (started by **Create scene**) runs in this order:
1. Splits the confirmed narration into scenes of about 10 seconds (`NarrationScenes`, no API calls).
2. Makes one planner call (`Ai::ScenePlanner`) that returns search queries for each scene. The
   planner is required: if it fails, each scene shows "Scene planning failed. Create scene again
   to retry." and no image search runs.
3. Searches Wikimedia Commons for each scene and stores up to 3 candidates with their credit,
   license and source page. Only Public domain, CC0, CC BY and CC BY-SA images are kept. Pixabay
   runs only when `PIXABAY_API_KEY` is set. Vision checks are not built.

**Review.** The Scenes page lists each scene as a card: thumbnail, source badge, license, credit and
narration, with **Swap image**, **Upload** and **Remove**. **Swap image** opens the side panel for that
scene, showing its candidates (click one to select it) and a free Commons search box. Uploads accept
JPEG, PNG or WebP up to 10 MB. **Approve scenes & continue** is enabled once every scene has an image;
it sets the project to `scenes_ready` and opens the Music step.

**AI images.** The swap panel's **AI generate** tab lets you describe an image and generate it for
credits (`CreditPricing.ai_image`, a placeholder of 5 until pricing is decided). Credits are charged
when you click **Generate**, and refunded automatically if generation fails. The prompt starts from
the planner's description of the scene, and safety rules are always added (no recognizable faces of
real people, no text or logos). Scenes the planner marked as showing a real person can't use AI
images. AI images are stored in Active Storage, labelled **AI**, and the project's
`settings["ai_images"]` is set so the description can say so.

**Credits.** `users.credits_balance` is the balance; `credit_transactions` records every change
(grants positive, charges negative, with the balance after). Charges lock the user row, so two
requests can't spend the same credits. Grant credits with
`bin/rails "credits:grant[test@example.com,20]"`. There is no purchase flow yet.

Commons uses `api.wikimedia.org` (search), `en.wikipedia.org` (metadata and license) and
`upload.wikimedia.org` (files). These work from networks that block `commons.wikimedia.org`.
Requests back off on HTTP 429 using `Retry-After` (at most 3 attempts).

The planner runs only when the script or the narration length changes. Repeated clicks reuse the
stored plans, so they don't pay again. Each planner call is recorded in `ApiUsage` as `scene_plan`.
Tests use fakes and clear `OPENAI_API_KEY`, so they never make a paid call.

### Music (step 4)

The Music page searches Wikimedia Commons for audio (`Media::CommonsAudioSearch`, no key), keeping
Public domain, CC0, CC BY and CC BY-SA tracks between 1 and 15 minutes and under 40 MB. The default
search follows the project's tone. **Use this track** stores the choice and `PrepareMusicTrackJob`
downloads it from `upload.wikimedia.org` (the only host accepted) and measures it with ffprobe.
Uploads accept MP3, M4A, WAV, OGG or FLAC up to 40 MB. **Continue** sets the project to
`media_ready`; a track that is still being prepared must finish first. Music search is cached for
an hour.

### Render (step 5)

`RenderVideoJob` builds the MP4 with ffmpeg (`Media::Ffmpeg`), at no API cost:
1. **Fit.** Each scene's image is fitted to 16:9. Images close to 16:9 (width/height 1.45–2.2) fill
   the frame with a small crop. Portraits, squares and very wide images are shown whole over a
   blurred, darkened copy of themselves, so nothing important is cut off.
2. **Motion.** Each scene slowly zooms 7%, alternating in and out. The image is worked at double
   size first so the zoom doesn't jitter. Each clip lasts an exact number of frames at 30 fps, so
   the clips add up to the narration's length.
3. **Captions.** When on (the default; a checkbox on the Render page), `Captions::AssBuilder` writes
   an ASS file from the word timings: 1–3 upper-case words at a time in the bundled Anton font,
   numbers and names in yellow, over a dark band, with the YouTube title (if written) as a hook
   over the first 2.8 seconds. This needs ffmpeg with libass; without it, the render finishes
   without captions and the page explains why.
4. **Sound.** The narration is added; music, if any, loops underneath at its volume, ducks while
   the voice speaks, and fades in and out. The final mix is normalised to −14 LUFS.
5. A light vignette is added, and a 1280x720 thumbnail is taken from the first second.

Remote images are downloaded at render time (`Media::Download`: HTTPS only, follows redirects,
backs off on 429, 30 MB limit). Progress is broadcast to the page ("Preparing scene 3 of 12...").
If rendering fails, the reason is shown and any earlier video is kept. Rendered files are stored
with Active Storage (`storage/` in development). The production Docker image installs Debian's
ffmpeg, which includes libass; the fonts ship in `fonts/` (Anton, SIL Open Font License).

### Publish (step 6)

**Write details** runs `GenerateMetadataJob`: one JSON call to the text model
(`Ai::MetadataGenerator`) for a title (max 100 characters), description, up to 15 tags (max 450
characters in total) and one YouTube category. `VideoDescription` then appends, from the
project's own data: "Narration is AI-generated.", "Some images are AI-generated." (when an AI
image is used), image credits for every Commons image, and the music credit. The details are
editable, **Copy all details** copies them as one block, and the MP4 and thumbnail download from
the page.

### Captions (SRT)

Voice generation makes one speech request per paragraph (`NarrationParts`; a paragraph over the
4,096-character limit is split at sentences) and measures each part with ffprobe. The track stores
each part's text, start and end (`audio_tracks.timings`), scaled to the joined file's length.
TTS is billed per character, so this costs the same as before.

`Captions::WordTimings` spreads each part's words across its span, weighted by word length: exact
at paragraph boundaries, close in between. `Captions::Srt` groups words into one-line cues of up
to 42 characters, ending at sentence or clause breaks (a sentence's last word may run 8 characters
over rather than sit alone). Voice tracks made before part timings fall back to spreading the whole
script across the narration; the Publish page says when timing is approximate, and regenerating
the voice makes it accurate.

The same word timings drive the burned-in captions (see Render).

### Voice generation

`VoicesController#create` stores the chosen voice and speed on the project's `AudioTrack` and
enqueues `GenerateVoiceJob`. The job:

1. Splits the latest script into chunks of at most 4,096 characters, breaking only at sentence
   boundaries (`NarrationChunker`).
2. Synthesizes each chunk through `Ai::SpeechGenerator`, broadcasting "Generating part N of M...".
3. Joins the MP3 parts with ffmpeg without re-encoding (`Media::Ffmpeg#concat`) and reads the
   duration with ffprobe.
4. Attaches the MP3 (replacing any earlier file), sets the track `ready`, the project
   `voice_ready`, and `settings["ai_voice"]`, and records an `ApiUsage` row.

On any error the track is marked `failed` with a readable message. A missing ffmpeg produces
"ffmpeg is not installed. Install it with `brew install ffmpeg`...".

Voice samples are shipped as files in `public/voice_samples/`, so previews make no API calls.
They were generated once with `bin/rails voice_samples:generate`, which skips voices that already
have a file. Run it again after adding a voice. Previews play at the chosen speed in the browser,
so moving the slider costs nothing. The final narration sends `voice` and `speed` to OpenAI.

### Provider boundary

Callers never talk to OpenAI directly. Everything goes through the service objects, so a provider
can be swapped in one place:

- `Ai::TextGenerator` (scripts, planner, YouTube details), `Ai::SpeechGenerator` (narration and samples),
  `Ai::ImageGenerator` (AI scene images)
- `Ai::OpenaiClient` builds the shared OpenAI client
- `Ai::Error` is the one error class callers rescue
- `Media::Ffmpeg` wraps ffmpeg and ffprobe; `Media::Download`, `Media::CommonsSearch` and
  `Media::CommonsAudioSearch` handle Wikimedia

### Routes

| Method            | Path                           | What it does                              |
| ----------------- | ------------------------------ | ----------------------------------------- |
| GET               | `/`                            | Projects list                             |
| GET, POST         | `/projects`, `/projects/new`   | List and create projects (`generate=1` also starts the script) |
| GET               | `/projects/:id`                | Project page: script, wizard, narration voice |
| POST, PATCH       | `/projects/:id/script`         | Generate or rewrite; autosave             |
| GET               | `/projects/:id/voice`          | Voice tab: generated voice and narration voice box |
| GET               | `/projects/:id/scenes`         | Scenes: timed scenes and their free images |
| POST              | `/projects/:id/scenes`         | Create scenes and find free images (background job) |
| POST              | `/projects/:id/voice`          | Generate, regenerate, retry               |
| POST              | `/projects/:id/voice/confirm`  | Confirm the generated voice               |
| POST              | `/projects/:id/scenes/approve` | Approve scenes (every scene needs an image) |
| POST              | `/scenes/:id/images`, `/scenes/:id/search`, `/scenes/:id/ai_image` | Upload, search Commons, generate an AI image |
| GET, POST, PATCH, DELETE | `/projects/:id/music`   | Music library; choose, volume, remove     |
| POST              | `/projects/:id/music/upload`, `/continue` | Upload a track; continue to render |
| GET, POST         | `/projects/:id/render`         | Render page; start a render               |
| GET, PATCH        | `/projects/:id/publish`        | Publish page; save YouTube details        |
| POST              | `/projects/:id/publish/generate` | Write YouTube details with AI           |
| GET               | `/projects/:id/publish/captions` | Download SRT captions                   |
| POST              | `/voice_samples?voice_name=…`  | Generate (once) and play a voice sample   |
| `/users/*`        | Devise                         | Sign up, sign in, sign out, password reset |

### Authentication

[Devise](https://github.com/heartcombo/devise) handles sign-up, sign-in (with "keep me signed in"),
sign-out and password reset. Sign-in and sign-up are rate limited in `app/controllers/users/`.
Reset links expire after 15 minutes. Every project page checks ownership, so one user cannot
open another user's projects.

## Pricing and limits

See [docs/COSTS.md](docs/COSTS.md) for what each script and voice costs, the free items, and the
expense log. In short: a 5-minute script costs well under a cent, and its voice-over about 7 cents.

- **Text:** `Ai::TextGenerator::PRICING_PER_MILLION` holds per-token prices for `gpt-4o-mini`.
- **Speech:** `Ai::SpeechGenerator::PRICE_PER_MILLION_CHARACTERS` holds `tts-1` at $15 and
  `tts-1-hd` at $30 per million characters, taken from OpenAI's pricing page.
- Update these constants when you change models or when prices change. The app uses them only
  for the estimates it records.

## Known gaps and unverified details

- **Speech input limit:** `Ai::SpeechGenerator::MAX_INPUT_CHARACTERS` is 4,096. The OpenAI API
  reference page could not be read while writing this, so confirm the limit before relying on it.
- **Voice list:** `Ai::SpeechGenerator::VOICES` holds the nine voices `tts-1` accepts. The names
  were confirmed from the API's own validation message. The short descriptions are ours.
- **Stuck jobs:** if the worker process dies during a voice run, the track stays `processing` and
  the page offers no reset. A timeout or cleanup task would fix this.
- **Sample usage:** voice samples are generated without a project, so their cost is not recorded
  in `ApiUsage`.
- **Browser check:** the UI has been checked through tests and HTTP requests, not in a browser on
  every screen size.
- **Credits:** only AI images charge credits, at a placeholder price. Credits are granted by hand
  (`bin/rails credits:grant`); there is no purchase flow.
- **Stuck renders:** if the worker dies mid-render, the project stays `rendering`. A timeout or
  cleanup task would fix this (same as stuck voice jobs).
- **Still images only:** scenes don't use video clips yet.
- **Worker restarts:** after a migration, restart `bin/dev`. A worker that started before the
  migration doesn't see the new columns and its jobs fail.
- **Production:** not set up. Storage uses local disk, and production needs its own database
  password and deployment config.

## Troubleshooting

| Symptom                                                        | Cause and fix                                                                                   |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Script or voice shows "OPENAI_API_KEY is not set"              | `.env` is missing the key, or the value is empty. Set it in `.env`, then restart `bin/dev`.    |
| Script shows "status 429" (quota or rate limit)              | OpenAI has no usable API credit. A card on file is not a credit balance: add prepaid credits under **Settings → Billing**. Nothing is charged for a rejected call. |
| Script or voice shows "Speech/Text generation failed: ..."     | Read the message after the colon. Quota errors mean billing or credits need attention.          |
| Voice shows "ffmpeg is not installed"                          | Run `brew install ffmpeg-full`, then restart `bin/dev`.                                         |
| Render page says captions would be skipped                     | The ffmpeg in use has no libass. Install `ffmpeg-full` (see Requirements).                      |
| `ffmpeg` in the terminal fails with "Library not loaded: libx265" | Homebrew upgraded a shared library. Run `brew upgrade ffmpeg`. The app keeps working via ffmpeg-full. |
| "Generating..." or "Starting..." never finishes                | The `jobs` process is not running. Start `bin/dev`, or run `bin/jobs` in another terminal.     |
| `Address already in use` on port 3000                          | Another process holds the port. Run `PORT=3100 bin/dev`.                                        |
| Sign-in page is unstyled                                       | Run `bin/rails tailwindcss:build` once, or keep `bin/dev` running for the CSS watcher.         |
| Password reset link not found                                  | Development does not send mail. Look in `log/development.log`.                                 |
| Sign-in attempts say "Too many sign-in attempts"               | Rate limit reached (10 per 3 minutes). Wait a few minutes.                                      |
| A job fails with "unknown attribute" right after a migration    | The worker started before the migration. Restart `bin/dev`.                                     |
| Render fails with "upload.wikimedia.org could not be used"      | The image host can't be reached from this network. Swap or upload that scene's image, then render again. |
