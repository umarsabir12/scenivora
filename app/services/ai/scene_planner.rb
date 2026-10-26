module Ai
  # Asks the text model for one search plan per scene, in a single call per project.
  # Commons is the only source in v1; Pixabay and vision checks come later (see docs/TODO.md).
  class ScenePlanner
    Plan = Data.define(:position, :visual_intent, :subject_type, :search_queries, :ai_fallback_allowed)
    Result = Data.define(:plans, :total_tokens, :cost_usd)

    SUBJECT_TYPES = %w[real_person real_place historical_event object generic_scene abstract].freeze
    MAX_QUERIES = 3

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the visual director for a documentary-style video. Input: a topic and a narration
      split into numbered scenes ("beats"), each with its duration in seconds.

      Return a JSON object with one entry per beat, in this shape:
      {"beats": [
        {
          "beat": <number>,
          "visual_intent": "<one sentence: what the viewer should see>",
          "subject_type": "real_person" | "real_place" | "historical_event" | "object" | "generic_scene" | "abstract",
          "search_queries": ["<1-3 concrete queries: proper names, places, dates>"],
          "ai_fallback_allowed": true | false
        }
      ]}

      Rules:
      - Queries must be concrete ("Mullaghmore harbour Sligo", "Westminster Abbey 1979"), never vague ("sad scene").
      - Real people: search for real photos first, and set ai_fallback_allowed to false for close-ups of a real person.
      - Never plan graphic violence, injuries or bodies. Use symbolic visuals instead (empty room, sea, candles).
      - Do not use the same subject_type for more than 3 beats in a row.
      - Return only the JSON object.
    PROMPT

    def self.estimated_cost(script_text, scene_count)
      model = ENV.fetch("OPENAI_TEXT_MODEL", Ai::TextGenerator::DEFAULT_MODEL)
      rates = Ai::TextGenerator::PRICING_PER_MILLION.fetch(model, { input: 0, output: 0 })
      input_tokens = SYSTEM_PROMPT.length / 4 + script_text.split.size * 4 / 3 + scene_count * 30
      output_tokens = scene_count * 80
      ((input_tokens * rates[:input] + output_tokens * rates[:output]) / 1_000_000).to_d.round(5)
    end

    def initialize(generator: Ai::TextGenerator.new)
      @generator = generator
    end

    # scenes: records with position, text and duration_ms.
    def call(topic:, scenes:)
      result = @generator.call(system_prompt: SYSTEM_PROMPT, user_prompt: user_prompt(topic, scenes),
                               temperature: 0.2, json: true)

      Result.new(plans: parse(result.text, scenes), total_tokens: result.total_tokens, cost_usd: result.cost_usd)
    end

    private
      def user_prompt(topic, scenes)
        beats = scenes.map { |scene| "Beat #{scene.position} (#{(scene.duration_ms / 1000.0).round(1)} s): #{scene.text}" }
        "Topic: #{topic}\n\n#{beats.join("\n")}"
      end

      # Scenes the model skipped or answered badly get an empty plan, so the caller can fall back.
      def parse(text, scenes)
        data = JSON.parse(text)
        beats = data.is_a?(Hash) ? Array(data["beats"]) : []
        by_number = beats.index_by { |beat| beat["beat"].to_i }

        scenes.to_h do |scene|
          beat = by_number[scene.position] || {}
          [ scene.position, plan_for(scene.position, beat) ]
        end
      rescue JSON::ParserError
        raise Ai::Error, "Scene planner returned invalid JSON"
      end

      def plan_for(position, beat)
        subject = beat["subject_type"].to_s
        Plan.new(
          position: position,
          visual_intent: beat["visual_intent"].to_s,
          subject_type: SUBJECT_TYPES.include?(subject) ? subject : "generic_scene",
          search_queries: Array(beat["search_queries"]).map { |q| q.to_s.strip }.reject(&:empty?).first(MAX_QUERIES),
          ai_fallback_allowed: beat["ai_fallback_allowed"] == true
        )
      end
  end
end
