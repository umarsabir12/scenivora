module Ai
  # Asks the text model for one search plan per scene, in a single call per project.
  # Commons is the only source in v1; Pixabay and vision checks come later (see docs/TODO.md).
  class ScenePlanner
    DEPICTIONS = %w[normal no_face no_figure].freeze

    Plan = Data.define(:position, :visual_intent, :subject_type, :search_queries, :ai_fallback_allowed, :prefer, :depiction,
                       :articles) do
      def initialize(prefer: "image", depiction: "normal", articles: [], **rest)
        super
      end
    end
    # topic_depiction: the rule the whole video needs, applied to every scene at least.
    # articles: Wikipedia articles about the whole topic; their pictures form the project's library.
    Result = Data.define(:plans, :total_tokens, :cost_usd, :topic_depiction, :articles) do
      def initialize(topic_depiction: "normal", articles: [], **rest)
        super
      end
    end

    SUBJECT_TYPES = %w[real_person real_place historical_event object generic_scene abstract].freeze
    MAX_QUERIES = 4
    MAX_TOPIC_ARTICLES = 6
    MAX_BEAT_ARTICLES = 2

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the visual director for a documentary-style video. Input: a topic and a narration
      split into numbered scenes ("beats"), each with its duration in seconds.

      Return a JSON object with the video's depiction rule and one entry per beat, in this shape:
      {"topic_depiction": "normal" | "no_face" | "no_figure",
       "articles": ["<up to 6 exact English Wikipedia article titles about the topic>"],
       "beats": [
        {
          "beat": <number>,
          "visual_intent": "<one sentence: what the viewer should see>",
          "subject_type": "real_person" | "real_place" | "historical_event" | "object" | "generic_scene" | "abstract",
          "search_queries": ["<4 queries, from specific to broad; the last is 1-3 words, usually the main name or place>"],
          "ai_fallback_allowed": true | false,
          "prefer": "video" | "image",
          "depiction": "normal" | "no_face" | "no_figure",
          "articles": ["<0-2 exact English Wikipedia article titles for this beat's subject>"]
        }
      ]}

      Rules:
      - Articles: their pictures are searched first, so name the articles about the people, places,
        ships, buildings and events the video shows. Use the exact English Wikipedia article title.
        Add the disambiguation in brackets for ships, people and places that share a name, e.g.
        'HMS Calypso (D61)', 'Prince Philip, Duke of Edinburgh'. Do not invent articles. If unsure
        one exists, leave it out.
      - Queries must be concrete ("Mullaghmore harbour Sligo", "Westminster Abbey 1979"), never vague ("sad scene").
      - The image search matches every word, so keep queries short and drop abstract words such as
        "symbolism", "chaos", "concept" or "legacy". Example: ["Lahore Resolution 1940", "Minar-e-Pakistan", "Lahore"].
      - Search the way an archive labels its photos: use the specific names of places, structures,
        machines, ships, people and events, not generic descriptions. For digging the Panama Canal write
        "Culebra Cut steam shovel", not "workers digging canal"; for a disease campaign name the doctor
        ("William Gorgas") or the work ("mosquito extermination Panama").
      - Real people: search for real photos first, and set ai_fallback_allowed to false for close-ups of a real person.
      - Never plan graphic violence, injuries or bodies. Use symbolic visuals instead (empty room, sea, candles).
      - Do not use the same subject_type for more than 3 beats in a row.
      - Depiction of revered religious figures: use "no_figure" for any scene that involves a prophet
        (for example the Prophet Muhammad, Jesus or Moses): they must not be shown in any form. Use
        "no_face" for scenes centred on the Prophet's companions (Sahaba), the Ahl al-Bayt, saints or
        other figures many believers would not want depicted: they may appear only from behind, in
        silhouette or far away. Everything else is "normal". For "no_figure" and "no_face" beats the
        visual_intent must already follow the rule (e.g. "cavalry silhouettes on a ridge at dawn").
      - topic_depiction is the rule for the whole video: "no_face" when the video is about a companion
        of the Prophet or another revered figure (every scene then follows it, including battles and
        maps), "no_figure" when it is about a prophet, otherwise "normal".
      - Prefer video for beats 1 and 2 (the hook) and for action: travel, crowds, vehicles, weather,
        battles, ceremonies. Prefer images for portraits and documents.
      - Return only the JSON object.
    PROMPT

    def self.estimated_cost(script_text, scene_count)
      model = ENV.fetch("OPENAI_TEXT_MODEL", Ai::TextGenerator::DEFAULT_MODEL)
      rates = Ai::TextGenerator::PRICING_PER_MILLION.fetch(model, { input: 0, output: 0 })
      input_tokens = SYSTEM_PROMPT.length / 4 + script_text.split.size * 4 / 3 + scene_count * 30
      output_tokens = scene_count * 95 + 40
      ((input_tokens * rates[:input] + output_tokens * rates[:output]) / 1_000_000).to_d.round(5)
    end

    def initialize(generator: Ai::TextGenerator.new)
      @generator = generator
    end

    # scenes: records with position, text and duration_ms.
    def call(topic:, scenes:)
      result = @generator.call(system_prompt: SYSTEM_PROMPT, user_prompt: user_prompt(topic, scenes),
                               temperature: 0.2, json: true)

      data = parse_json(result.text)
      Result.new(plans: plans_from(data, scenes), total_tokens: result.total_tokens, cost_usd: result.cost_usd,
                 topic_depiction: DEPICTIONS.include?(data["topic_depiction"]) ? data["topic_depiction"] : "normal",
                 articles: titles(data["articles"], MAX_TOPIC_ARTICLES))
    end

    private
      def user_prompt(topic, scenes)
        beats = scenes.map { |scene| "Beat #{scene.position} (#{(scene.duration_ms / 1000.0).round(1)} s): #{scene.text}" }
        "Topic: #{topic}\n\n#{beats.join("\n")}"
      end

      def parse_json(text)
        data = JSON.parse(text)
        data.is_a?(Hash) ? data : {}
      rescue JSON::ParserError
        raise Ai::Error, "Scene planner returned invalid JSON"
      end

      # Scenes the model skipped or answered badly get an empty plan, so the caller can fall back.
      def plans_from(data, scenes)
        by_number = Array(data["beats"]).index_by { |beat| beat["beat"].to_i }

        scenes.to_h do |scene|
          beat = by_number[scene.position] || {}
          [ scene.position, plan_for(scene.position, beat) ]
        end
      end

      def plan_for(position, beat)
        subject = beat["subject_type"].to_s
        Plan.new(
          position: position,
          visual_intent: beat["visual_intent"].to_s,
          subject_type: SUBJECT_TYPES.include?(subject) ? subject : "generic_scene",
          search_queries: Array(beat["search_queries"]).map { |q| q.to_s.strip }.reject(&:empty?).first(MAX_QUERIES),
          ai_fallback_allowed: beat["ai_fallback_allowed"] == true,
          prefer: beat["prefer"] == "video" ? "video" : "image",
          depiction: DEPICTIONS.include?(beat["depiction"]) ? beat["depiction"] : "normal",
          articles: titles(beat["articles"], MAX_BEAT_ARTICLES)
        )
      end

      def titles(list, limit)
        Array(list).map { |title| title.to_s.squish }.reject(&:empty?).uniq.first(limit)
      end
  end
end
