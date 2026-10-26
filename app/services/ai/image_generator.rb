require "base64"

module Ai
  # The only place that talks to an image-generation provider. Callers depend on Result and Error,
  # so the provider can be swapped by changing this class.
  class ImageGenerator
    Error = Ai::Error

    Result = Data.define(:image, :content_type, :provider, :model, :cost_usd)

    PROVIDER = "openai".freeze
    DEFAULT_MODEL = "gpt-image-1-mini".freeze
    SIZE = "1536x1024".freeze # landscape, closest to 16:9
    QUALITY = "medium".freeze

    # USD per one million tokens, from OpenAI's pricing page (checked 2026-10-26).
    PRICING_PER_MILLION = {
      "gpt-image-1-mini" => { text_input: 2.00, image_input: 2.50, image_output: 8.00 }
    }.freeze

    # Added to every prompt: the same rules the scene planner follows.
    SAFETY_RULES = "Photorealistic documentary still. Do not show a recognizable face of any real person: " \
                   "show people from behind, in silhouette, or only hands and objects. No text, captions, " \
                   "signs, logos, watermarks, flags or religious symbols. No graphic violence or injuries.".freeze

    def initialize(model: ENV.fetch("OPENAI_IMAGE_MODEL", DEFAULT_MODEL), client: nil)
      @model = model
      @client = client
    end

    def call(prompt:)
      response = client.images.generate(parameters: {
        model: model, prompt: "#{prompt.strip}\n\n#{SAFETY_RULES}", size: SIZE, quality: QUALITY, n: 1
      })

      encoded = response.dig("data", 0, "b64_json")
      raise Error, "Provider returned no image" if encoded.blank?

      Result.new(image: Base64.decode64(encoded), content_type: "image/png", provider: PROVIDER, model: model,
                 cost_usd: cost_for(response.fetch("usage", {})))
    rescue OpenAI::Error, Faraday::Error => e
      raise Error, "Image generation failed: #{e.message}"
    end

    private
      attr_reader :model

      def client
        @client ||= Ai::OpenaiClient.build
      end

      def cost_for(usage)
        prices = PRICING_PER_MILLION.fetch(model) do
          Rails.logger.warn("No image pricing configured for #{model}; recording $0 cost")
          return 0.to_d
        end

        details = usage.fetch("input_tokens_details", {})
        text_tokens = details.fetch("text_tokens", usage.fetch("input_tokens", 0))
        image_input_tokens = details.fetch("image_tokens", 0)
        output_tokens = usage.fetch("output_tokens", 0)

        total = text_tokens * prices[:text_input] + image_input_tokens * prices[:image_input] +
                output_tokens * prices[:image_output]
        (total / 1_000_000).to_d.round(6)
      end
  end
end
