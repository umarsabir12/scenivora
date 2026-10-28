require "test_helper"

class GenerateVoiceJobTest < ActiveJob::TestCase
  # Fake speech provider: returns numbered MP3 stand-ins and can be told to fail.
  class FakeSpeech
    attr_reader :calls

    def initialize(error: nil)
      @calls = []
      @error = error
    end

    def call(text:, voice:, speed:)
      raise @error if @error

      @calls << { text: text, voice: voice, speed: speed }
      Ai::SpeechGenerator::Result.new(
        audio: "MP3-PART-#{@calls.size}",
        provider: "openai",
        model: "tts-1",
        characters: text.length,
        cost_usd: BigDecimal("0.001")
      )
    end
  end

  # Fake ffmpeg: concatenates the part bytes into the output and reports a fixed duration.
  class FakeFfmpeg
    DURATION_MS = 90_500

    attr_reader :joined_parts

    def concat(part_paths, output_path)
      @joined_parts = part_paths.map { |path| File.read(path) }
      File.binwrite(output_path, @joined_parts.join)
      output_path
    end

    def duration_ms(_path)
      DURATION_MS
    end
  end

  class FailingFfmpeg < FakeFfmpeg
    def concat(*)
      raise Media::Ffmpeg::Error, "ffmpeg is not installed. Install it with `brew install ffmpeg`, then restart the worker."
    end
  end

  setup do
    @user = users(:one)
    @project = @user.projects.create!(prompt: "How the Nile flooded", tone: "dramatic", target_length_minutes: 6)
    @body = Array.new(260) { |i| "Sentence number #{i} keeps the story moving forward." }.join(" ")
    @script = @project.scripts.create!(body: @body, version: 1)
    @project.script_ready!
    @track = @project.audio_tracks.create!(kind: "voice", voice_name: "shimmer", speed: 1.1)
  end

  def run_job(speech: FakeSpeech.new, ffmpeg: FakeFfmpeg.new)
    with_stubbed_new(Ai::SpeechGenerator, speech) do
      with_stubbed_new(Media::Ffmpeg, ffmpeg) do
        GenerateVoiceJob.perform_now(@track)
      end
    end
  end

  test "splits the script into chunks, synthesizes each, and joins them into one attached MP3" do
    speech = FakeSpeech.new

    run_job(speech: speech)

    assert speech.calls.size > 1, "a long script should need several requests"
    assert speech.calls.all? { |call| call[:text].length <= Ai::SpeechGenerator::MAX_INPUT_CHARACTERS }
    assert speech.calls.all? { |call| call[:voice] == "shimmer" && call[:speed] == 1.1 }
    assert_equal @body.split, speech.calls.map { |call| call[:text] }.join(" ").split

    @track.reload
    assert @track.ready?
    assert_equal 90_500, @track.duration_ms
    assert @track.file.attached?
    assert_equal "audio/mpeg", @track.file.content_type
    assert_equal @script.digest, @track.script_digest
  end

  test "marks the project voice_ready and flags its metadata as AI narrated" do
    run_job

    @project.reload
    assert @project.voice_ready?
    assert_equal true, @project.settings["ai_voice"]
  end

  test "records characters sent and estimated cost as usage" do
    speech = FakeSpeech.new

    run_job(speech: speech)

    usage = @project.api_usages.sole
    assert_equal "voice", usage.operation
    assert_equal "openai", usage.provider
    assert_equal speech.calls.sum { |call| call[:text].length }, usage.units
    assert_equal BigDecimal("0.001") * speech.calls.size, usage.cost_usd
  end

  test "marks the track failed with the provider's message" do
    run_job(speech: FakeSpeech.new(error: Ai::Error.new("Speech generation failed: rate limited")))

    @track.reload
    assert @track.failed?
    assert_equal "Speech generation failed: rate limited", @track.error
    assert_not @track.file.attached?
    assert @project.reload.script_ready?
  end

  test "marks the track failed with an install hint when ffmpeg is missing" do
    run_job(ffmpeg: FailingFfmpeg.new)

    @track.reload
    assert @track.failed?
    assert_match "brew install ffmpeg", @track.error
  end

  test "a failed regeneration keeps the previously attached narration" do
    run_job
    previous_blob_id = @track.reload.file.blob.id

    run_job(speech: FakeSpeech.new(error: Ai::Error.new("boom")))

    @track.reload
    assert @track.failed?
    assert @track.file.attached?
    assert_equal previous_blob_id, @track.file.blob.id
  end

  test "fails cleanly when there is no script" do
    @script.destroy!
    @project.reload

    run_job

    assert @track.reload.failed?
    assert_equal "There is no script to narrate yet.", @track.error
  end

  test "a successful run makes an earlier voice stale once the script is edited" do
    run_job
    @script.update!(body: "A brand new narration after the edit.")

    assert @track.reload.stale_for?(@project.latest_script)
  end

  test "makes one part per paragraph and stores each part's timing" do
    @script.update!(body: "First paragraph about the Nile.\n\nSecond paragraph about the flood.")
    @track.update!(script_digest: @script.reload.digest)
    speech = FakeSpeech.new

    run_job(speech: speech)

    assert_equal [ "First paragraph about the Nile.", "Second paragraph about the flood." ], speech.calls.map { |call| call[:text] }
    timings = @track.reload.timings
    assert_equal [ "First paragraph about the Nile.", "Second paragraph about the flood." ], timings.map { |part| part["text"] }
    assert_equal 0, timings.first["start_ms"]
    assert_equal timings.first["end_ms"], timings.last["start_ms"]
    assert_equal 90_500, timings.last["end_ms"]
  end
end
