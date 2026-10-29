module Ai
  # The one model responsible for a video's pictures.
  #
  # Planning: it researches the real history on Wikipedia first (the facts, and the exact titles of
  # the articles about the people, places, ships and events), then plans every scene in the same
  # shape as the scene planner. Article titles are checked against Wikipedia afterwards, so invented
  # ones never reach the search.
  #
  # Review: after the search, it looks at the whole storyboard at once and catches what one-scene
  # checks miss (wrong era, generic or repeated pictures, a pick that contradicts the facts). For
  # each scene it keeps the picture, swaps in another candidate, or rejects it with an AI prompt.
  class Director
    # facts: what the research established, shown to later steps. dropped_articles: titles that
    # don't exist on Wikipedia and were removed.
    Plan = Data.define(:result, :facts, :searches, :dropped_articles)
    # action: "keep", "swap" (to candidate_id) or "reject". ai_prompt: for scenes left without a picture.
    Decision = Data.define(:action, :candidate_id, :note, :ai_prompt)
    Review = Data.define(:decisions, :total_tokens, :cost_usd)
    ACTIONS = %w[keep swap reject].freeze
    MAX_ALTERNATIVES = 6

    DOMAINS = %w[en.wikipedia.org].freeze
    MAX_SEARCHES = 8
    MAX_FACTS = 12

    RESEARCH_PROMPT = <<~PROMPT.freeze
      You are the director of a documentary video and you are responsible for every picture in it
      being right. Before planning, research the real history behind the narration on Wikipedia:
      the real people, places, ships, buildings and events, their dates, and the exact titles of the
      Wikipedia articles about them. The narration may be vague ("a ship", "his mother") or slightly
      wrong about dates; plan from what really happened. Search only for what you are unsure of.

      Then plan the video as the visual director described below. Add one field to the top level
      of the JSON object:
       "facts": ["<up to 12 short facts from your research that the pictures depend on, with dates>"]

    PROMPT

    # Set OPENAI_DIRECTOR_MODEL=off to plan with the cheap scene planner only.
    def self.enabled?
      ENV["OPENAI_DIRECTOR_MODEL"] != "off"
    end

    # Measured on a 12-scene video with gpt-5.5: $0.26 (28k tokens, 3 searches). Research reads
    # search results, so input is mostly fixed; reasoning grows with the scene count.
    def self.estimated_cost(scene_count)
      model = ENV.fetch("OPENAI_DIRECTOR_MODEL", Ai::ResearchGenerator::DEFAULT_MODEL)
      rates = Ai::ResearchGenerator::PRICING_PER_MILLION.fetch(model, { input: 0, output: 0 })
      input_tokens = 18_000 + scene_count * 400
      output_tokens = 1_500 + scene_count * 250
      tokens = (input_tokens * rates[:input] + output_tokens * rates[:output]) / 1_000_000
      (tokens.to_d + 4 * Ai::ResearchGenerator::PRICE_PER_SEARCH).round(4)
    end

    REVIEW_PROMPT = <<~PROMPT.freeze
      You are the director of a documentary video and you are responsible for every picture in it
      being right. You get the facts your research established and the storyboard: for each scene
      its narration, what it should show, its depiction rule, its current picture (shown as an
      image, labelled [picture N]) and the other candidates found for it (by title only).

      Judge the storyboard as a whole, as a viewer would watch it. Reject or swap a picture when:
      - it shows a different person, place, ship or event than the scene, or contradicts the facts;
      - it is from the wrong era (a modern photo for a scene about the subject's childhood);
      - it is generic, only loosely related, or about someone else (a photo of other famous people
        when the scene is about the subject's own story);
      - it repeats or nearly repeats another scene's picture;
      - it breaks the scene's depiction rule (no_face: no face of the revered figure; no_figure:
        the figure not shown in any form).
      Swap only to a candidate whose title clearly shows the right subject and era, and never to a
      candidate another scene already shows. Keep a picture that is right; do not reject for small
      things. Scenes marked "fixed" were chosen by the user: decide "keep" for them.

      For every scene left without a picture (rejected, or none found), write an ai_prompt: one or
      two sentences describing a period-accurate image of the scene, following its depiction rule.

      Return only JSON:
      {"scenes": [{"scene": <number>, "action": "keep" | "swap" | "reject",
                   "candidate": <candidate id, for swap only>,
                   "note": "<one short sentence for the user explaining the decision>",
                   "ai_prompt": "<only for scenes left without a picture>"}]}
    PROMPT

    def initialize(generator: Ai::ResearchGenerator.new, titles: Media::WikipediaTitles.new, planner: Ai::ScenePlanner.new,
                   previews: Media::PreviewFetcher.new)
      @generator = generator
      @titles = titles
      @planner = planner
      @previews = previews
    end

    # scenes: records with position, text and duration_ms.
    def plan(topic:, scenes:)
      response = @generator.call(instructions: RESEARCH_PROMPT + Ai::ScenePlanner::SYSTEM_PROMPT,
                                 input: Ai::ScenePlanner.user_prompt(topic, scenes),
                                 domains: DOMAINS, max_searches: MAX_SEARCHES)
      data = parse_json(response.text)
      result = @planner.result_from(data, scenes, total_tokens: response.total_tokens, cost_usd: response.cost_usd)
      result, dropped = with_real_articles(result)

      Plan.new(result: result, facts: Array(data["facts"]).map { |fact| fact.to_s.squish }.reject(&:empty?).first(MAX_FACTS),
               searches: response.searches, dropped_articles: dropped)
    end

    # scenes: the project's scenes with their images. fixed: positions the Director must not change.
    # Returns a Decision per scene it answered for; ids it gives are checked against each scene's own
    # candidates.
    def review(topic:, scenes:, facts:, fixed: [])
      lines = []
      images = []
      scenes.each do |scene|
        pick = scene.selected_image
        jpeg = pick && preview(pick)
        images << jpeg if jpeg
        lines << storyboard_entry(scene, pick, jpeg && images.size, fixed.include?(scene.position))
      end

      input = "Topic: #{topic}\n\nFacts:\n#{Array(facts).map { |fact| "- #{fact}" }.join("\n")}\n\nStoryboard:\n#{lines.join("\n\n")}"
      response = @generator.call(instructions: REVIEW_PROMPT, input: input, images: images, effort: "low")
      data = parse_json(response.text, required: "scenes")
      Review.new(decisions: decisions_from(data, scenes), total_tokens: response.total_tokens, cost_usd: response.cost_usd)
    end

    private
      # The answer may carry text or a code fence around the JSON when the model has searched.
      def parse_json(text, required: "beats")
        data = JSON.parse(text[/\{.*\}/m].to_s)
        raise Ai::Error, "Director returned no #{required}" unless data.is_a?(Hash) && data[required].is_a?(Array)

        data
      rescue JSON::ParserError
        raise Ai::Error, "Director returned invalid JSON"
      end

      def storyboard_entry(scene, pick, picture_number, fixed)
        current =
          if pick.nil? then "none"
          elsif picture_number then "[picture #{picture_number}] #{describe(pick)}"
          else "(no preview) #{describe(pick)}"
          end
        others = scene.images.reject { |media| media.selected? || media.stored_file? }.first(MAX_ALTERNATIVES)
        [
          "Scene #{scene.position} (#{(scene.duration_ms / 1000.0).round} s, rule: #{scene.depiction})#{" fixed" if fixed}",
          "  Narration: #{scene.text}",
          "  Should show: #{scene.plan["visual_intent"].presence || scene.text}",
          "  Current picture: #{current}",
          "  Other candidates: #{others.any? ? others.map { |media| "##{media.id} #{describe(media)}" }.join("; ") : "none"}"
        ].join("\n")
      end

      def describe(media)
        details = [ ("taken #{media.taken_on}" if media.taken_on.present?),
                    ("from Wikipedia article \"#{media.source_article}\"" if media.source_article.present?),
                    ("the user's own upload or AI image" if media.stored_file?) ].compact
        "\"#{media.source_title}\"#{" (#{details.join("; ")})" if details.any?}"
      end

      def preview(media)
        @previews.jpeg(media)
      rescue Media::Error, Media::Ffmpeg::Error => e
        Rails.logger.warn("No preview for #{media.id} in the storyboard review: #{e.message}")
        nil
      end

      def decisions_from(data, scenes)
        by_position = scenes.index_by(&:position)
        data["scenes"].each_with_object({}) do |entry, decisions|
          scene = by_position[entry["scene"].to_i]
          next unless scene && ACTIONS.include?(entry["action"])

          candidate_id = entry["candidate"].to_s.delete("#").to_i
          candidate_id = nil unless entry["action"] == "swap" && scene.images.any? { |media| media.id == candidate_id }
          next if entry["action"] == "swap" && candidate_id.nil?

          decisions[scene.position] = Decision.new(action: entry["action"], candidate_id: candidate_id,
                                                   note: entry["note"].to_s.squish.first(300),
                                                   ai_prompt: entry["ai_prompt"].to_s.squish.first(1000).presence)
        end
      end

      # Swaps each title for the article's real title (after redirects) and drops the ones that
      # don't exist. If Wikipedia can't be reached, the titles are kept as given.
      def with_real_articles(result)
        named = result.articles + result.plans.values.flat_map(&:articles)
        real = @titles.resolve(named)
        fix = ->(list) { list.filter_map { |title| real.fetch(title, title) }.uniq }

        plans = result.plans.transform_values { |plan| plan.with(articles: fix.call(plan.articles)) }
        [ result.with(plans: plans, articles: fix.call(result.articles)), named.uniq.select { |title| real.key?(title) && real[title].nil? } ]
      rescue Media::Error => e
        Rails.logger.warn("Could not check article titles: #{e.message}")
        [ result, [] ]
      end
  end
end
