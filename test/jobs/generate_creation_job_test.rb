require "test_helper"

class GenerateCreationJobTest < ActiveJob::TestCase
  # Fake speech provider: numbered MP3 stand-ins, or an error.
  class FakeSpeech
    attr_reader :calls

    def initialize(error: nil)
      @calls = []
      @error = error
    end

    def call(text:, voice:, speed:)
      raise @error if @error

      @calls << { text: text, voice: voice, speed: speed }
      Ai::SpeechGenerator::Result.new(audio: "MP3-PART-#{@calls.size}", provider: "openai", model: "tts-1",
                                      characters: text.length, cost_usd: BigDecimal("0.001"))
    end
  end

  # Fake ffmpeg: joins the part bytes and reports a fixed duration.
  class FakeFfmpeg
    DURATION_MS = 42_000

    def concat(part_paths, output_path)
      File.binwrite(output_path, part_paths.map { |path| File.read(path) }.join)
    end

    def duration_ms(_path) = DURATION_MS
  end

  setup do
    @user = users(:one)
    @user.update!(credits_balance: 5)
  end

  def speech_creation(prompt: "Tides follow the moon.")
    Creation.start!(@user, kind: "speech", model_key: "openai-tts-1", prompt: prompt,
                           options: { "voice" => "sage", "speed" => "1.1" })
  end

  def run_job(creation, speech: FakeSpeech.new, ffmpeg: FakeFfmpeg.new)
    with_stubbed_new(Ai::SpeechGenerator, speech) do
      with_stubbed_new(Media::Ffmpeg, ffmpeg) { GenerateCreationJob.perform_now(creation) }
    end
  end

  test "voices long text in parts, joins them into one MP3 and records the cost" do
    text = Array.new(250) { |i| "Sentence #{i} carries the story on." }.join(" ")
    @user.update!(credits_balance: 20)
    creation = speech_creation(prompt: text)
    speech = FakeSpeech.new

    run_job(creation, speech: speech)

    creation.reload
    assert creation.ready?
    assert speech.calls.size > 1
    assert speech.calls.all? { |call| call[:voice] == "sage" && call[:speed] == 1.1 }
    assert_equal text.split, speech.calls.map { |call| call[:text] }.join(" ").split
    assert creation.file.attached?
    assert_equal FakeFfmpeg::DURATION_MS, creation.duration_ms
    usage = creation.api_usages.sole
    assert_equal [ "openai", "create_speech", speech.calls.sum { |call| call[:text].length } ], [ usage.provider, usage.operation, usage.units ]
    assert_nil usage.project_id
  end

  test "a failure refunds the credits and shows the reason" do
    creation = speech_creation
    assert_equal 4, @user.reload.credits_balance

    run_job(creation, speech: FakeSpeech.new(error: Ai::Error.new("The voice provider is down.")))

    assert creation.reload.failed?
    assert_equal "The voice provider is down.", creation.error
    assert_equal 5, @user.reload.credits_balance
    assert_equal "create_speech_refund", @user.credit_transactions.last.reason
  end

  test "a creation that already ran is not run or refunded again" do
    creation = speech_creation
    creation.update!(status: "failed")

    run_job(creation, speech: FakeSpeech.new(error: Ai::Error.new("should not be called")))

    assert_equal 4, @user.reload.credits_balance
  end
end
