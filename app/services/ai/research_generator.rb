require "base64"

module Ai
  # The strong model's call, through OpenAI's Responses API: used for research, the script written
  # from it, and the Director. For research it may search the web first, limited to the domains
  # given, so the model can check facts and exact article titles rather than rely on its memory.
  # For the storyboard review it looks at pictures instead.
  class ResearchGenerator
    Result = Data.define(:text, :provider, :model, :total_tokens, :cost_usd, :searches)

    PROVIDER = "openai".freeze
    DEFAULT_MODEL = "gpt-5.5".freeze
    # USD per one million tokens. Keep in sync with the provider's price list. Search results the
    # model reads are billed as input; its reasoning is billed as output.
    PRICING_PER_MILLION = {
      "gpt-5.5" => { input: 5.00, output: 30.00 },
      "gpt-4.1" => { input: 2.00, output: 8.00 },
      "gpt-5-mini" => { input: 0.25, output: 2.00 }
    }.freeze
    PRICE_PER_SEARCH = BigDecimal("0.01")
    # Research with searches takes longer than a plain text call.
    REQUEST_TIMEOUT_SECONDS = 300

    def initialize(model: ENV.fetch("OPENAI_DIRECTOR_MODEL", DEFAULT_MODEL), client: nil)
      @model = model
      @client = client
    end

    # domains: where the model may search, e.g. ["en.wikipedia.org"]; nil means no searching.
    # max_searches caps the searches. images: JPEG bytes shown at low detail, after the input text.
    # effort: reasoning effort for models that reason (gpt-5 family); ignored by the others.
    def call(instructions:, input:, domains: nil, max_searches: 8, images: [], effort: "medium")
      parameters = { model: model, instructions: instructions, input: input_with(input, images) }
      if domains
        parameters[:tools] = [ { type: "web_search", filters: { allowed_domains: domains } } ]
        parameters[:max_tool_calls] = max_searches
      end
      parameters[:reasoning] = { effort: effort } if reasoning_model?

      build_result(client.responses.create(parameters: parameters))
    rescue OpenAI::Error, Faraday::Error => e
      raise Ai::Error.from(e, "Research call failed")
    end

    private
      attr_reader :model

      def client
        @client ||= Ai::OpenaiClient.build(request_timeout: REQUEST_TIMEOUT_SECONDS)
      end

      def input_with(text, images)
        return text if images.empty?

        content = [ { type: "input_text", text: text } ] + images.map do |jpeg|
          { type: "input_image", image_url: "data:image/jpeg;base64,#{Base64.strict_encode64(jpeg)}", detail: "low" }
        end
        [ { role: "user", content: content } ]
      end

      def reasoning_model?
        model.start_with?("gpt-5", "o")
      end

      def build_result(response)
        output = Array(response["output"])
        text = output.select { |item| item["type"] == "message" }
                     .flat_map { |item| Array(item["content"]) }
                     .select { |part| part["type"] == "output_text" }
                     .map { |part| part["text"] }.join("\n").strip
        raise Ai::Error, "Provider returned an empty response" if text.empty?

        usage = response.fetch("usage", {})
        searches = output.count { |item| item["type"] == "web_search_call" }
        Result.new(text: text, provider: PROVIDER, model: model, total_tokens: usage.fetch("total_tokens", 0),
                   cost_usd: estimate_cost(usage, searches), searches: searches)
      end

      def estimate_cost(usage, searches)
        prices = PRICING_PER_MILLION.fetch(model) do
          Rails.logger.warn("No pricing configured for #{model}; recording search cost only")
          { input: 0, output: 0 }
        end

        tokens = usage.fetch("input_tokens", 0) * prices[:input] + usage.fetch("output_tokens", 0) * prices[:output]
        ((tokens / 1_000_000).to_d + searches * PRICE_PER_SEARCH).round(6)
      end
  end
end
