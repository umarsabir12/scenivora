module Ai
  # The only place that talks to a text-to-speech provider. Callers depend on
  # Result and Error, so the provider can be swapped by changing this class.
  class SpeechGenerator
    Error = Ai::Error

    Result = Data.define(:audio, :provider, :model, :characters, :cost_usd)

    PROVIDER = "openai".freeze
    DEFAULT_MODEL = "tts-1".freeze
    # Per-request input limit for OpenAI's speech endpoint. Unverified against the current
    # API docs (the docs page was not reachable); confirm before relying on it.
    MAX_INPUT_CHARACTERS = 4096
    SPEED_RANGE = (0.25..4.0).freeze

    # Voice name => short description for the voice picker. Names are the voices the `tts-1`
    # model accepts (checked against the API's own validation message). Descriptions are ours.
    VOICES = {
      "alloy" => "Neutral and balanced",
      "ash" => "Warm and conversational",
      "coral" => "Bright and friendly",
      "echo" => "Clear and direct",
      "fable" => "Warm and storytelling",
      "nova" => "Energetic and upbeat",
      "onyx" => "Deep and authoritative",
      "sage" => "Calm and measured",
      "shimmer" => "Gentle and airy"
    }.freeze

    # USD per one million input characters. Source: OpenAI pricing page.
    PRICE_PER_MILLION_CHARACTERS = {
      "tts-1" => 15.00,
      "tts-1-hd" => 30.00
    }.freeze

    def initialize(model: ENV.fetch("OPENAI_SPEECH_MODEL", DEFAULT_MODEL), client: nil)
      @model = model
      @client = client
    end

    def call(text:, voice:, speed: 1.0)
      raise Error, "Unknown voice: #{voice}" unless VOICES.key?(voice)
      raise Error, "Text is #{text.length} characters; the limit is #{MAX_INPUT_CHARACTERS}" if text.length > MAX_INPUT_CHARACTERS

      audio = client.audio.speech(parameters: {
        model: model,
        input: text,
        voice: voice,
        speed: speed,
        response_format: "mp3"
      })
      raise Error, "Provider returned no audio" if audio.blank?

      Result.new(audio: audio, provider: PROVIDER, model: model, characters: text.length, cost_usd: cost_for(text.length))
    rescue OpenAI::Error, Faraday::Error => e
      raise Error, "Speech generation failed: #{e.message}"
    end

    private
      attr_reader :model

      def client
        @client ||= Ai::OpenaiClient.build
      end

      def cost_for(characters)
        rate = PRICE_PER_MILLION_CHARACTERS.fetch(model) do
          Rails.logger.warn("No speech pricing configured for #{model}; recording $0 cost")
          0
        end

        (characters * rate / 1_000_000).to_d.round(6)
      end
  end
end
