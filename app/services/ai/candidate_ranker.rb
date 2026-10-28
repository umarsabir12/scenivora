module Ai
  # Checks free image and video candidates against their scenes using the candidates' titles
  # (Wikimedia file names are descriptive), in one JSON call per project. Cheaper than looking at
  # the pictures, and catches most mismatches: wrong person, wrong era, unrelated places.
  class CandidateRanker
    Result = Data.define(:kept, :total_tokens, :cost_usd) # kept: { scene_position => [candidate ids, best first] }

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You pick stock media for a documentary. For each scene you get the narration and a list of
      candidate images and videos, identified by id and file title.

      Keep only candidates that plausibly show the scene's subject: the right person, place, object,
      event or era. Leave out anything that merely shares a word with it: a different person, a modern
      aircraft for a 1903 scene, an unrelated building, a satellite or weather image, a map of the
      wrong place. Use the description, date and categories when given:
      - A photo taken decades after the scene's time (an anniversary, a memorial, a museum visit) does
        not show a historical moment. But when the scene is about lasting effects or today ("today it
        stands as...", "it changed trade forever"), modern photos of the subject are right.
      - When the scene is about a specific place, keep a candidate only if its title, description or
        categories mention that place (or a place inside it). Machinery, buildings or crowds from
        somewhere else don't count, however similar they look.
      Order the kept ids best first. A scene may keep none.

      Return only JSON: {"scenes": [{"scene": <number>, "keep": [<ids>]}]}
    PROMPT

    def initialize(generator: Ai::TextGenerator.new)
      @generator = generator
    end

    # scenes: records with position, text, plan and images (candidates with id, media_type, source_title).
    def call(topic:, scenes:)
      result = @generator.call(system_prompt: SYSTEM_PROMPT, user_prompt: user_prompt(topic, scenes), temperature: 0, json: true)
      Result.new(kept: parse(result.text, scenes), total_tokens: result.total_tokens, cost_usd: result.cost_usd)
    end

    private
      def user_prompt(topic, scenes)
        blocks = scenes.map do |scene|
          lines = scene.images.reject(&:stored_file?).map { |media| "  #{media.id} [#{media.media_type}] #{candidate_details(media)}" }
          "Scene #{scene.position}: #{scene.plan["visual_intent"].presence || scene.text}\n#{lines.join("\n")}"
        end
        "Topic: #{topic}\n\n#{blocks.join("\n\n")}"
      end

      def candidate_details(media)
        parts = [ media.source_title ]
        parts << "taken: #{media.taken_on}" if media.taken_on.present?
        parts << "description: #{media.description}" if media.description.present?
        parts << "categories: #{media.categories}" if media.categories.present?
        parts.join(" | ")
      end

      # Only ids that really belong to the scene are accepted, in the order given.
      def parse(text, scenes)
        data = JSON.parse(text)
        entries = data.is_a?(Hash) ? Array(data["scenes"]) : []
        by_position = entries.index_by { |entry| entry["scene"].to_i }

        scenes.to_h do |scene|
          valid = scene.images.map(&:id)
          kept = Array(by_position.dig(scene.position, "keep")).map(&:to_i).select { |id| valid.include?(id) }.uniq
          [ scene.position, kept ]
        end
      rescue JSON::ParserError
        raise Ai::Error, "Candidate check returned invalid JSON"
      end
  end
end
