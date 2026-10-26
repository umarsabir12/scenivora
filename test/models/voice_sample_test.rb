require "test_helper"

class VoiceSampleTest < ActiveSupport::TestCase
  # Counts calls so tests can prove the provider is only hit once per voice.
  class CountingGenerator
    attr_reader :calls

    def initialize
      @calls = 0
    end

    def call(text:, voice:, speed: 1.0)
      @calls += 1
      Ai::SpeechGenerator::Result.new(audio: "SAMPLE", provider: "openai", model: "tts-1", characters: text.length, cost_usd: 0)
    end
  end

  test "generates a sample once and reuses it on later requests" do
    generator = CountingGenerator.new

    first = VoiceSample.generate_for("nova", generator: generator)
    second = VoiceSample.generate_for("nova", generator: generator)

    assert_equal 1, generator.calls
    assert_equal first, second
    assert first.file.attached?
    assert_equal "SAMPLE", first.file.download
  end

  test "keeps one sample per voice" do
    generator = CountingGenerator.new

    VoiceSample.generate_for("nova", generator: generator)
    VoiceSample.generate_for("echo", generator: generator)

    assert_equal 2, VoiceSample.count
    assert_equal 2, generator.calls
  end

  test "shipped sample files are found by voice name" do
    assert_equal "/voice_samples/alloy.mp3", VoiceSample.static_url("alloy")
    assert_nil VoiceSample.static_url("not-a-voice")
  end

  test "every voice the picker offers has a shipped sample" do
    Ai::SpeechGenerator::VOICES.each_key do |voice|
      assert VoiceSample.static_url(voice), "missing public/voice_samples/#{voice}.mp3"
    end
  end

  test "rejects unknown voice names" do
    sample = VoiceSample.new(voice_name: "nobody")

    assert_not sample.valid?
  end
end
