module Ai
  # Looks at a scene's best candidates (small previews) and picks one that truly fits the scene,
  # or none. This is what keeps off-topic, wrong-era or watermarked pictures out of the video.
  class ImageVerifier
    Result = Data.define(:choice_id, :reason, :total_tokens, :cost_usd)

    LETTERS = %w[A B C].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You check pictures for one scene of a documentary video. You get the scene's narration, what the
      viewer should see, and candidate pictures labelled A, B and C with their file titles.

      Pick the picture that shows what this scene is about. Be strict: a viewer should see the picture
      and recognise the moment being narrated. Reject a picture when:
      - it shows a different subject, person, place or event than the scene describes;
      - it is from a different era than the scene: a modern photo (an anniversary, a memorial, a museum,
        a replica, a modern aircraft or car) does not show a historical moment, even if the subject is
        similar. Use "taken" dates when given;
      - it is only "related to the theme" (any aircraft for a scene about the Wright brothers' designs,
        any crowd for a specific celebration). That is not enough;
      - its title shows it is from a different place than the scene, even if it looks right;
      - it is mostly text, a document page, a chart or a logo, unless the scene is about that;
      - it has a large watermark, burned-in subtitles or channel branding;
      - it is graphic or disturbing;
      - it is blurry, tiny or badly damaged.
      A symbolic picture is fine only when the scene itself is about an idea rather than a specific
      moment, and it must still fit the scene's era. When the scene is about lasting effects or today,
      a modern photo of the subject is right. You cannot identify people from their faces: judge
      people by context, clothing, era and the file title. If no picture is right, choose none.

      Return only JSON: {"choice": "A" | "B" | "C" | null, "reason": "<one short sentence>"}
    PROMPT

    def initialize(generator: Ai::TextGenerator.new, previews: Media::PreviewFetcher.new)
      @generator = generator
      @previews = previews
    end

    # candidates: the scene's sourced candidates, best first. Those without a usable preview are skipped.
    def call(scene:, candidates:)
      shown = []
      images = []
      candidates.each do |candidate|
        break if shown.size == LETTERS.size

        jpeg = preview(candidate)
        next unless jpeg

        shown << candidate
        images << jpeg
      end
      raise Ai::Error, "No candidate could be previewed" if shown.empty?

      result = @generator.call(system_prompt: SYSTEM_PROMPT, user_prompt: user_prompt(scene, shown),
                               temperature: 0, json: true, images: images)
      data = JSON.parse(result.text)
      index = LETTERS.index(data["choice"].to_s.strip.upcase) if data.is_a?(Hash)
      Result.new(choice_id: index && shown[index]&.id, reason: data.is_a?(Hash) ? data["reason"].to_s.first(300) : "",
                 total_tokens: result.total_tokens, cost_usd: result.cost_usd)
    rescue JSON::ParserError
      raise Ai::Error, "Picture check returned invalid JSON"
    end

    private
      def preview(candidate)
        @previews.jpeg(candidate)
      rescue Media::Error, Media::Ffmpeg::Error => e
        Rails.logger.warn("No preview for candidate #{candidate.id}: #{e.message}")
        nil
      end

      def user_prompt(scene, shown)
        lines = shown.each_with_index.map do |candidate, index|
          dated = candidate.taken_on.present? ? " (taken #{candidate.taken_on})" : ""
          "#{LETTERS[index]}: [#{candidate.media_type}] #{candidate.source_title}#{dated}"
        end
        "Narration: #{scene.text}\nShould show: #{scene.plan["visual_intent"].presence || scene.text}\n\n#{lines.join("\n")}"
      end
  end
end
