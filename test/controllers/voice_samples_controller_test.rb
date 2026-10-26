require "test_helper"

class VoiceSamplesControllerTest < ActionDispatch::IntegrationTest
  class CountingSpeech
    attr_reader :calls

    def initialize
      @calls = 0
    end

    def call(text:, voice:, speed: 1.0)
      @calls += 1
      Ai::SpeechGenerator::Result.new(audio: "SAMPLE-#{voice}", provider: "openai", model: "tts-1", characters: text.length, cost_usd: 0)
    end
  end

  class FailingSpeech
    def call(**)
      raise Ai::Error, "Speech generation failed: unavailable"
    end
  end

  setup do
    sign_in users(:one)
  end

  test "playing a sample generates it once and reuses it afterwards" do
    speech = CountingSpeech.new

    with_stubbed_new(Ai::SpeechGenerator, speech) do
      post voice_samples_url(voice_name: "coral"), as: :turbo_stream
      post voice_samples_url(voice_name: "coral"), as: :turbo_stream
    end

    assert_response :success
    assert_equal 1, speech.calls
    assert_equal 1, VoiceSample.where(voice_name: "coral").count
    assert_match "audio", response.body
  end

  test "a provider failure shows a message next to the voice" do
    with_stubbed_new(Ai::SpeechGenerator, FailingSpeech.new) do
      post voice_samples_url(voice_name: "ash"), as: :turbo_stream
    end

    assert_response :success
    assert_match "Speech generation failed: unavailable", response.body
  end

  test "unknown voices are rejected" do
    post voice_samples_url(voice_name: "nobody"), as: :turbo_stream

    assert_response :unprocessable_entity
  end
end
