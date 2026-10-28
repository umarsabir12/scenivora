module Ai
  # A second chance for scenes whose first searches found no fitting picture: writes new,
  # archive-style queries for all of them in one call.
  class QueryRewriter
    Result = Data.define(:queries, :total_tokens, :cost_usd) # queries: { scene_position => [queries] }

    MAX_QUERIES = 4

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You help find archive photos for a documentary. These scenes found no fitting picture with the
      queries shown. Write new search queries for each, the way an archive (Wikimedia Commons, the
      Library of Congress, national archives) labels its photos: specific names of places, structures,
      machines, ships, people, events and years. Avoid the words that already failed and avoid generic
      phrases like "workers", "history" or "impact". Example: for digging the Panama Canal, write
      "Culebra Cut steam shovel", "Culebra Cut 1910", "Gaillard Cut excavation".

      Return only JSON: {"scenes": [{"scene": <number>, "queries": ["<1-4 words>", ...up to 4]}]}
    PROMPT

    def initialize(generator: Ai::TextGenerator.new)
      @generator = generator
    end

    # scenes: records with position, text, plan (visual_intent, search_queries).
    def call(topic:, scenes:)
      blocks = scenes.map do |scene|
        "Scene #{scene.position}: #{scene.text}\nShould show: #{scene.plan["visual_intent"]}\n" \
          "Failed queries: #{Array(scene.plan["search_queries"]).join("; ")}"
      end
      result = @generator.call(system_prompt: SYSTEM_PROMPT, user_prompt: "Topic: #{topic}\n\n#{blocks.join("\n\n")}",
                               temperature: 0.4, json: true)
      Result.new(queries: parse(result.text, scenes), total_tokens: result.total_tokens, cost_usd: result.cost_usd)
    end

    private
      def parse(text, scenes)
        data = JSON.parse(text)
        by_position = (data.is_a?(Hash) ? Array(data["scenes"]) : []).index_by { |entry| entry["scene"].to_i }
        scenes.to_h do |scene|
          queries = Array(by_position.dig(scene.position, "queries")).map { |query| query.to_s.squish }.reject(&:empty?)
          [ scene.position, queries.first(MAX_QUERIES) ]
        end
      rescue JSON::ParserError
        raise Ai::Error, "Query rewrite returned invalid JSON"
      end
  end
end
