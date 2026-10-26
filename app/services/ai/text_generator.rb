module Ai
  # The only place that talks to a text-generation provider. Callers depend on
  # Result and Error, so the provider can be swapped by changing this class.
  class TextGenerator
    Error = Ai::Error

    Result = Data.define(:text, :provider, :model, :total_tokens, :cost_usd)

    PROVIDER = "openai".freeze
    DEFAULT_MODEL = "gpt-4o-mini".freeze
    # USD per one million tokens. Keep in sync with the provider's price list.
    PRICING_PER_MILLION = {
      "gpt-4o-mini" => { input: 0.15, output: 0.60 }
    }.freeze

    def initialize(model: ENV.fetch("OPENAI_TEXT_MODEL", DEFAULT_MODEL), client: nil)
      @model = model
      @client = client
    end

    def call(system_prompt:, user_prompt:, temperature: 0.8)
      response = client.chat(parameters: {
        model: model,
        temperature: temperature,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt }
        ]
      })

      build_result(response)
    rescue OpenAI::Error, Faraday::Error => e
      raise Error, "Text generation failed: #{e.message}"
    end

    private
      attr_reader :model

      def client
        @client ||= Ai::OpenaiClient.build
      end

      def build_result(response)
        text = response.dig("choices", 0, "message", "content").to_s.strip
        raise Error, "Provider returned an empty response" if text.empty?

        usage = response.fetch("usage", {})
        Result.new(
          text: text,
          provider: PROVIDER,
          model: model,
          total_tokens: usage.fetch("total_tokens", 0),
          cost_usd: estimate_cost(usage)
        )
      end

      def estimate_cost(usage)
        prices = PRICING_PER_MILLION.fetch(model) do
          Rails.logger.warn("No pricing configured for #{model}; recording $0 cost")
          { input: 0, output: 0 }
        end

        input_cost = usage.fetch("prompt_tokens", 0) * prices[:input]
        output_cost = usage.fetch("completion_tokens", 0) * prices[:output]
        ((input_cost + output_cost) / 1_000_000).to_d.round(6)
      end
  end
end
