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
| `OPENAI_DIRECTOR_MODEL` | No    | `gpt-5.5`     | The Director, which researches and plans scene pictures; `off` uses the cheap planner |
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

Creating videos (research, script, storyboard, pictures), voices, AI images, music downloads, renders and YouTube details run in background jobs. If the `jobs` process is not running,
the page shows "Generating..." or "Starting..." until it starts.

## Using the app

1. **Sign up or sign in.** Password reset emails are not sent through a mail service in
   development. Open `log/development.log` and copy the reset link from the email.
2. **Dashboard.** Type a brief in "What's your next video about?", optionally add instructions
   ("Focus on the escape"), pick a category, tone and length, and click **Create video**. The
   project opens on its storyboard straight away, which shows the progress (about 5 to 10
   minutes; measured 8.5 minutes for a 3-minute video with 21 scenes): researching and writing the script, finding and checking a picture for each scene,
   and starting AI images (up to 8, paid in credits) where no real picture fits. Filter the
   list with All, In progress or Rendered.
3. **Storyboard.** One card per scene (one short paragraph of narration, one picture). Edit a
   scene's narration and **Save text**, **Delete scene**, swap, upload or generate an AI image for
   its picture. **Rewrite storyboard** writes a new script and storyboard for the same brief (the
   research is reused). When every scene has a picture, **Approve storyboard & choose voice**.
   Scene times are estimated from the words until the voice is made.
4. **Voice.** Pick a voice, play its sample, set the speed from 0.85x to 1.15x, check the
   estimated cost, and click **Generate voice**. The narration is voiced one scene at a time, with
   live progress ("Generating part 2 of 30..."). **Confirm voice** times every scene from its own
   part and opens Music. Editing the storyboard afterwards sends the project back to the
   storyboard, and the voice must be made again.
5. **Music.** Pick a free track from the music library (Wikimedia Commons), or upload your own,
   and set its volume (default 18%, up to 50%). Music is optional: **Continue without music**
   skips it.
6. **Render.** Choose whether to burn captions in (on by default), then click **Render video**. The
   MP4 (1920x1080, H.264, AAC, −14 LUFS) is built on this machine with ffmpeg, with progress shown
   live. A failed re-render keeps the previous video.
7. **Publish.** Watch the video, download the MP4 and thumbnail, and click **Write details** for an
   AI title, description, tags and category. Edit them, **Save details**, then **Copy all details**
   and upload to YouTube yourself. **Download captions (.srt)** gives a caption file to upload in
   YouTube Studio under Subtitles.

The app uses a dark theme only. Colors are set in `app/helpers/application_helper.rb` (form
fields and buttons) and in the views.

## Tests and checks

```sh
bin/rails test        # 391 tests: models, services, jobs, controllers, auth flows
bin/rubocop           # style (rubocop-rails-omakase)
bin/brakeman          # security scan
bin/ci                # all of the above, plus setup, importmap audit and seeds (Rails 8.1 local CI)
```

The tests never call OpenAI, Wikimedia or ffmpeg, so they need no API key, network or ffmpeg:
the providers, downloads and ffmpeg are replaced with fakes.

## How it works

### Data model

- `User`: Devise account, `credits_balance` (placeholder, shown in the top bar).
- `Project`: brief (`prompt`), optional `category` and `instructions`, `tone`, `target_length_minutes`, `status`
  (`draft → script_ready → scenes_ready → voice_ready → media_ready → rendering → rendered` for
  storyboard projects; see "Create video" below), and `settings` (JSON):
  `settings["production"]` holds the Create video step, `settings["storyboard"]` marks a
  storyboard project, `settings["research"]` the research, and `settings["ai_voice"]` is true
  after narration is generated, so the description can say "Narration is AI-generated".
- `Script`: versioned narration text, one paragraph per scene. Storyboard edits update the latest
  version in place; Rewrite storyboard adds a new version.
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
  Operations: `research`, `script`, `voice`, `director_plan`, `scene_plan`, `director_review`, `ai_image`, `metadata`.

### Create video

`ProjectsController#create` (and **Rewrite storyboard**, `ScenesController#rewrite`) call
`Project#start_production!`, which enqueues `ProduceVideoJob`. It runs, saving each step in
`settings["production"]["step"]` (`writing → pictures → ai_images → done`, or `failed`) and
refreshing the storyboard page:

- `ScriptWriter` writes the script (below), one short paragraph per shot.
- `StoryboardScenes` lays the paragraphs out as scenes (a paragraph over 45 words is split at
  sentences), timed from their words at 150 per minute; `settings["storyboard"]` marks the project.
- `FindSceneImagesJob` plans, finds, checks and reviews a picture for each scene (see below).
- AI images start for up to 8 "AI image suggested" scenes, hook scenes first, while the user's
  credits last; a note says how many are left.

Storyboard projects run storyboard (`script_ready`) → approved (`scenes_ready`) → voice confirmed
(`voice_ready`) → `media_ready` → `rendering` → `rendered`. Editing or deleting a scene
(`StoryboardScenesController`) rewrites the script from the scenes, estimates the times again,
unconfirms the voice and returns the project to the storyboard. The voice is generated one
paragraph (scene) at a time, so confirming it gives each scene its measured time. Projects made
before the storyboard keep the old order (script → voice → scenes).

### Script

`ScriptWriter`:

1. **Research first** (`Ai::Researcher`, about $0.50): the strong model searches English Wikipedia
   for the brief, its category and instructions, and returns up to 20 dated facts, checked article
   titles, up to 25 showable "visual subjects" (people, places, ships, buildings, documents) and
   uncertain claims. It is saved in `project.settings["research"]` and reused while the brief,
   category and instructions stay the same, so **Rewrite** doesn't pay for it again.
2. **Script from the research** (`OPENAI_SCRIPT_MODEL`, defaulting to the Director's `gpt-5.5`):
   the usual rules (hook in the first 15 seconds, a turning point, about 150 words per minute,
   plain narration only), plus: only facts from the research, uncertain items attributed, a
   visual subject named in every paragraph, no abstract "legacy" paragraphs, and the story the
   brief asks for. The prompt gives a word range (90-110% of the target); a script over 110% is
   shortened once by the same model.
3. If research or the strong model fails, or the Director is `off`, `Ai::TextGenerator`
   (`gpt-4o-mini`) writes from the brief alone, as before.

It saves the next `Script` version and records `research` and `script` usage. Later, the
Director's scene plan reads the same research (and the pictures found in its articles) instead
of searching again.

### Scene images (step 3)

**Create scene** offers two modes:
- **Real photos first** (default): free Wikimedia pictures, each checked by AI, with an AI image
  suggested where nothing real fits.
- **AI images for every scene**: no searching; every scene is marked "AI image suggested".

`FindSceneImagesJob` (real photos first) runs in this order:
1. Splits the confirmed narration into scenes of about 10 seconds (`NarrationScenes`, no API calls).
2. **The Director** (`Ai::Director`, one call with `OPENAI_DIRECTOR_MODEL`, about $0.26) first
   researches the real history on Wikipedia with OpenAI web search (at most 8 searches, Wikipedia
   only), then plans every scene. Its facts are saved in `project.settings["facts"]`, and every
   article title it names is checked against Wikipedia (`Media::WikipediaTitles`, free); titles that
   don't exist are dropped. If the Director fails, or every scene will be an AI image, the cheap
   planner (`Ai::ScenePlanner`) plans instead. A plan writes search queries per scene, whether it
   prefers video, and what the viewer should see. It also names up to 6 exact English Wikipedia articles for the
   topic (saved in `project.settings["articles"]`) and 0-2 per scene (in `scene.plan["articles"]`).
   If planning fails, the scenes ask to retry and nothing is searched.
3. **Article library** (`Media::ArticleLibrary`, free): fetches the pictures used in each named
   Wikipedia article once per video (`Media::WikipediaArticleImages`, one call per article, about a
   second each), keeps free-licence photos only, dedupes them and keeps about 60. Titles that don't
   exist are skipped with a log line.
4. Builds each scene's pool of up to 12 images: its own articles' pictures first, then library
   pictures sharing the most words with what the scene should show. Only when that pool has fewer
   than 5 does it search Wikimedia Commons with the planner's queries (written the way archives
   label photos), then broader forms (`Media::QueryVariants`) that always keep the subject's name,
   the year and at least 2 words. Server errors are retried. The first 2 scenes (the hook) and scenes
   marked `prefer: video` also search Commons video (360p or better, the planner's own queries only,
   and the title must share a real word with the query).
5. **Relevance check** (`Ai::CandidateRanker`, one text call per project, ~$0.0006): judges every
   candidate by its title, description, date and categories, removes off-topic ones and orders the rest.
   Rules: a modern photo doesn't show a historical moment (but is right for scenes about today), and for
   a scene about a specific place the candidate's metadata must mention that place.
6. **Picture check** (`Ai::ImageVerifier`, one call per scene with up to 6 small previews, ~$0.002 per
   scene; if that call fails, the first 3 are checked alone): looks at the pictures and keeps one only if it shows the scene's actual subject in the right
   era, without large watermarks or burned-in text. A kept picture is marked **✓ Checked**. If none
   passes, the scene's picture is deselected and the scene is marked **AI image suggested**, so nothing
   unchecked reaches the video. If the check itself fails, the scene is marked for manual review.
7. **Second chance** (`Ai::QueryRewriter`, one text call): scenes still without a picture get new
   archive-style queries and are searched (keyword search only, since they already saw the library),
   ranked and checked once more.
8. **Storyboard review** (`Ai::Director#review`, one call, about $0.05): the Director looks at every
   scene's picture together (small previews), with its facts, and keeps, swaps (to another
   candidate, which must still pass the picture check) or rejects each one. For scenes left
   without a picture it writes an AI image prompt (`scene.plan["ai_prompt"]`), which the AI
   generate tab starts from. Scenes the user chose or uploaded are never changed. If the review
   fails, the checked pictures stay.

A picture is used once per video, whichever source it came from.

Scenes waiting for an AI image can be generated one by one (AI generate tab) or together with
**Generate all suggested**, which shows the total credits first and only starts if the balance covers
all of them. Pictures you pick, upload or generate are marked as your choice and are not re-checked.

**Review.** The Scenes page lists each scene as a card: thumbnail, source badge, license, credit and
narration, with **Swap image**, **Upload** and **Remove**. **Swap image** opens the side panel for that
scene, showing its candidates (click one to select it) and a free Commons search box. Uploads accept
JPEG, PNG or WebP up to 10 MB. **Approve scenes & continue** is enabled once every scene has an image;
it sets the project to `scenes_ready` and opens the Music step. A scene waiting for an AI image has no
selected picture, so approval waits until it gets one.

**AI images.** The swap panel's **AI generate** tab lets you describe an image and generate it for
credits (`CreditPricing.ai_image`, a placeholder of 5 until pricing is decided). Credits are charged
when you click **Generate**, and refunded automatically if generation fails. The prompt starts from
the planner's description of the scene, and safety rules are always added (no recognizable faces of
real people, no text or logos). Scenes the planner marked as showing a real person are generated as
painted illustrations (oil-painting style), never photorealistic, so they can't pass as real photos. AI images are stored in Active Storage, labelled **AI**, and the project's
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
1. **Fit.** Each scene's image is fitted to a still slightly larger than 16:9. Images close to 16:9
   (width/height 1.45–2.2) fill it, cropped from 35% down where faces usually are; portraits,
   squares and very wide images are shown whole over a blurred copy. The still is lightly sharpened.
2. **Motion.** Each still zooms 7%, alternating in and out, sampled at fractional pixel positions
   every frame (ffmpeg `perspective`, cubic) so it glides instead of shaking. Measured
   unevenness: 0.043 (was 0.478 with `zoompan`). **Video** scenes are cut from their source
   instead: downloaded once per render (up to 150 MB), filled to 16:9 with 5% trimmed from every
   edge (removes most timecodes, banners and corner logos on 4:3 archive footage), and the last
   frame is held if the clip is shorter than the scene. Each clip lasts an exact number of frames
   at 30 fps, so the clips add up to the narration's length.
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
