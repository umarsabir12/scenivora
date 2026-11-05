module Ai
  # Plans the shots of a script from the project's media catalog in one call: for each paragraph the
  # catalog pictures to show, in order, or an AI image prompt when no picture fits. The pictures are
  # chosen by what they show (the catalog's descriptions), not by file names, and checked in code:
  # unknown, unusable and repeated ids are dropped, and AI prompts are capped.
  class ShotPlanner
    # shots: [Shot]. dropped: ids the model gave that don't exist, aren't usable or were used before.
    Result = Data.define(:shots, :dropped, :total_tokens, :cost_usd)
    # pictures: catalog entry hashes. ai_prompt: nil, or the illustration to make when no picture fits.
    Shot = Data.define(:paragraph, :text, :pictures, :ai_prompt)

    DEFAULT_MODEL = "gpt-5-mini".freeze
    MAX_PICTURES = 3

    PROMPT = <<~PROMPT.freeze
      You are the picture editor of a documentary video. You get its script, numbered by paragraph,
      and the catalog of real pictures it can use: an id and what each picture shows. For each
      paragraph choose the pictures to show while it is read, in order: 1 to 3, more for longer
      paragraphs.

      Rules:
      - A picture must show what the paragraph is about: the same person, team, place, event and
        era. A 2023 photo can't show a 2004 match; a picture of someone else can't show this person.
      - The team matters: a club shirt never shows a national-team moment, and a national shirt never
        shows a club moment. A wax figure, statue, mural or museum shows the person only when the
        paragraph is about that object.
      - Prefer pictures from the paragraph's own year. An empty or generic stadium, crowd or building
        only fits a paragraph about that place or crowd; for other paragraphs an AI image is better.
      - When the paragraph is about a moment no picture shows (a private decision, a statement, a
        dressing room), a picture of the same person or place from close to that time is right
        when it fits the mood; otherwise choose no pictures and write an AI image prompt.
      - Use each picture once in the whole video.
      - At most %<max_ai>d paragraphs get an AI image. Its prompt describes one documentary still in
        one or two sentences: the setting, light and objects, with people only from behind or in
        silhouette. No text, logos or real faces.

      Return only JSON:
      {"shots": [{"paragraph": <number>, "pictures": ["<id>", ...], "ai_prompt": "<prompt>" | null}]}
      One entry for every paragraph, in order.
    PROMPT

    def initialize(generator: Ai::ResearchGenerator.new(model: ENV.fetch("OPENAI_SHOT_MODEL", DEFAULT_MODEL)))
      @generator = generator
    end

    # paragraphs: the script's paragraph texts. catalog: entry hashes ("id", "shows", "year", "kind", "usable").
    def call(paragraphs:, catalog:, max_ai_images:)
      usable = catalog.select { |picture| picture["usable"] }.index_by { |picture| picture["id"] }
      response = @generator.call(instructions: format(PROMPT, max_ai: max_ai_images), input: input(paragraphs, usable.values),
                                 effort: "medium")
      planned = parse(response.text)
      used = Set.new
      dropped = []
      ai_left = max_ai_images

      shots = paragraphs.each_with_index.map do |text, index|
        plan = planned[index + 1] || {}
        ids = Array(plan["pictures"]).map(&:to_s)
        pictures = ids.filter_map { |id| usable[id] if used.add?(id) }.first(MAX_PICTURES)
        dropped.concat(ids - pictures.map { |picture| picture["id"] })
        prompt = plan["ai_prompt"].to_s.squish.presence if pictures.empty? && ai_left.positive?
        ai_left -= 1 if prompt
        Shot.new(paragraph: index + 1, text: text, pictures: pictures, ai_prompt: prompt)
      end
      Result.new(shots: shots, dropped: dropped.uniq, total_tokens: response.total_tokens, cost_usd: response.cost_usd)
    end

    private
      def input(paragraphs, pictures)
        script = paragraphs.each_with_index.map { |text, index| "#{index + 1}. #{text}" }.join("\n")
        listed = pictures.map do |picture|
          people = Array(picture["people"]).presence
          "#{picture["id"]}: #{picture["shows"]}#{" (#{picture["year"]})" if picture["year"].present?}#{" [#{people.join(", ")}]" if people}"
        end
        "Script:\n#{script}\n\nCatalog:\n#{listed.join("\n")}"
      end

      # paragraph number => the model's hash for it.
      def parse(text)
        data = JSON.parse(text.to_s[/\{.*\}/m].to_s)
        raise Ai::Error, "Shot planner returned no shots" unless data.is_a?(Hash) && data["shots"].is_a?(Array)

        data["shots"].select { |shot| shot.is_a?(Hash) }.index_by { |shot| shot["paragraph"].to_i }
      rescue JSON::ParserError
        raise Ai::Error, "Shot planner returned invalid JSON"
      end
  end
end
