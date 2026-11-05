module Ai
  # Plans the pictures of a project that has no stored research (projects made before research came
  # first). It researches the real history on Wikipedia (the facts, and the exact titles of the
  # articles about the people, places, ships and events), then plans every scene in the same shape
  # as the scene planner. Article titles are checked against Wikipedia afterwards, so invented ones
  # never reach the search. Projects with research are planned by the cheap scene planner instead.
  #
  # OPENAI_DIRECTOR_MODEL=off turns off both the Director and the research before the script.
  class Director
    # facts: what the research established, shown to later steps. dropped_articles: titles that
    # don't exist on Wikipedia and were removed.
    Plan = Data.define(:result, :facts, :searches, :dropped_articles)

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

    def initialize(generator: Ai::ResearchGenerator.new, titles: Media::WikipediaTitles.new, planner: Ai::ScenePlanner.new)
      @generator = generator
      @titles = titles
      @planner = planner
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

    private
      # The answer may carry text or a code fence around the JSON when the model has searched.
      def parse_json(text)
        data = JSON.parse(text[/\{.*\}/m].to_s)
        raise Ai::Error, "Director returned no beats" unless data.is_a?(Hash) && data["beats"].is_a?(Array)

        data
      rescue JSON::ParserError
        raise Ai::Error, "Director returned invalid JSON"
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
