require "test_helper"

class Ai::SpeechGeneratorTest < ActiveSupport::TestCase
  FakeAudio = Struct.new(:response) do
    attr_reader :parameters

    def speech(parameters:)
      @parameters = parameters
      response
    end
  end

  FakeClient = Struct.new(:audio)

  setup do
    @audio = FakeAudio.new("MP3-BYTES")
    @generator = Ai::SpeechGenerator.new(model: "tts-1", client: FakeClient.new(@audio))
  end

  test "returns the audio with characters and estimated cost" do
    text = "a" * 1_000

    result = @generator.call(text: text, voice: "alloy", speed: 1.1)

    assert_equal "MP3-BYTES", result.audio
    assert_equal 1_000, result.characters
    # 1,000 characters at $15 per million
    assert_equal BigDecimal("0.015"), result.cost_usd
    assert_equal "openai", result.provider
  end

  test "sends the voice, speed and mp3 format to the API" do
    @generator.call(text: "Hello.", voice: "fable", speed: 0.9)

    assert_equal({ model: "tts-1", input: "Hello.", voice: "fable", speed: 0.9, response_format: "mp3" },
      @audio.parameters)
  end

  test "rejects unknown voices" do
    error = assert_raises(Ai::SpeechGenerator::Error) do
      @generator.call(text: "Hello.", voice: "nobody")
    end

    assert_match "Unknown voice", error.message
  end

  test "rejects text over the per-request character limit" do
    text = "a" * (Ai::SpeechGenerator::MAX_INPUT_CHARACTERS + 1)

    error = assert_raises(Ai::SpeechGenerator::Error) do
      @generator.call(text: text, voice: "alloy")
    end

    assert_match "limit is #{Ai::SpeechGenerator::MAX_INPUT_CHARACTERS}", error.message
  end

  test "raises when the provider returns no audio" do
    generator = Ai::SpeechGenerator.new(model: "tts-1", client: FakeClient.new(FakeAudio.new("")))

    assert_raises(Ai::SpeechGenerator::Error) { generator.call(text: "Hi.", voice: "alloy") }
  end
end
