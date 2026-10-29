module Ai
  # Researches a video's topic on Wikipedia before the script is written, so the script tells what
  # really happened and names things that can be shown. The result is stored on the project and
  # reused by the script, the Director's plan and the picture library.
  class Researcher
    # visual_subjects: [{ "name", "kind", "article" (nil if none exists), "year" }].
    # uncertain: legends and single-source claims, to attribute or leave out.
    Research = Data.define(:facts, :articles, :visual_subjects, :uncertain, :total_tokens, :cost_usd, :searches,
                           :dropped_articles) do
      def to_settings(key)
        { "key" => key, "facts" => facts, "articles" => articles, "visual_subjects" => visual_subjects, "uncertain" => uncertain }
      end
    end

    DOMAINS = %w[en.wikipedia.org].freeze
    MAX_SEARCHES = 10
    MAX_FACTS = 20
    MAX_ARTICLES = 12
    MAX_SUBJECTS = 25
    MAX_UNCERTAIN = 8
    KINDS = %w[person place ship building object document event].freeze

    PROMPT = <<~PROMPT.freeze
      You research the topic of a documentary video before its script is written. Search English
      Wikipedia for what really happened: the people, places, ships, buildings, objects, documents
      and events involved, with dates. Search only for what you are unsure of.

      Return only a JSON object:
      {"facts": ["<up to 20 short facts with dates, in story order>"],
       "articles": ["<up to 12 exact English Wikipedia article titles about the topic's subjects>"],
       "visual_subjects": [{"name": "<a concrete thing a viewer could be shown>",
                            "kind": "person" | "place" | "ship" | "building" | "object" | "document" | "event",
                            "article": "<its exact Wikipedia article title, or null>",
                            "year": "<the year that matters for this video, or null>"}],
       "uncertain": ["<legends, disputed or single-source claims, saying who claims them>"]}

      Rules:
      - Facts only from your research, never from the brief alone: briefs can be wrong.
      - Visual subjects: up to 25 concrete, showable things (HMS Calypso, Mon Repos villa, a
        1922 newspaper), not ideas (exile, courage, legacy).
      - Use exact article titles, with the disambiguation in brackets when names are shared, e.g.
        'HMS Calypso (D61)'. Do not invent articles.
    PROMPT

    def initialize(generator: Ai::ResearchGenerator.new, titles: Media::WikipediaTitles.new)
      @generator = generator
      @titles = titles
    end

    # Identifies "this brief": research is reused while the brief, category and instructions stay the same.
    def self.key_for(project)
      Digest::SHA256.hexdigest([ project.prompt, project.category, project.instructions ].map(&:to_s).join("\n"))
    end

    def call(project)
      response = @generator.call(instructions: PROMPT, input: input_for(project), domains: DOMAINS, max_searches: MAX_SEARCHES)
      data = parse_json(response.text)
      articles, subjects, dropped = with_real_articles(strings(data["articles"], MAX_ARTICLES), subjects_from(data["visual_subjects"]))

      Research.new(facts: strings(data["facts"], MAX_FACTS), articles: articles, visual_subjects: subjects,
                   uncertain: strings(data["uncertain"], MAX_UNCERTAIN), total_tokens: response.total_tokens,
                   cost_usd: response.cost_usd, searches: response.searches, dropped_articles: dropped)
    end

    private
      def input_for(project)
        lines = [ "Brief: #{project.prompt}" ]
        lines << "Category: #{project.category} (#{Project::CATEGORIES[project.category]})" if project.category.present?
        lines << "The creator's instructions: #{project.instructions}" if project.instructions.present?
        lines << "Target length: #{project.target_length_minutes} minutes"
        lines.join("\n")
      end

      def parse_json(text)
        data = JSON.parse(text[/\{.*\}/m].to_s)
        raise Ai::Error, "Research returned no facts" unless data.is_a?(Hash) && data["facts"].is_a?(Array)

        data
      rescue JSON::ParserError
        raise Ai::Error, "Research returned invalid JSON"
      end

      def strings(list, limit)
        Array(list).map { |item| item.to_s.squish }.reject(&:empty?).uniq.first(limit)
      end

      def subjects_from(list)
        Array(list).filter_map do |subject|
          next unless subject.is_a?(Hash) && subject["name"].to_s.squish.present?

          { "name" => subject["name"].to_s.squish, "kind" => subject["kind"].presence_in(KINDS) || "object",
            "article" => subject["article"].to_s.squish.presence, "year" => subject["year"].to_s.squish.presence }
        end.uniq { |subject| subject["name"].downcase }.first(MAX_SUBJECTS)
      end

      # Real titles only (after redirects). A subject whose article doesn't exist keeps its name.
      # If Wikipedia can't be reached, the titles are kept as given.
      def with_real_articles(articles, subjects)
        real = @titles.resolve(articles + subjects.filter_map { |subject| subject["article"] })
        fix = ->(title) { real.fetch(title, title) }
        dropped = real.select { |_, found| found.nil? }.keys

        [ articles.filter_map(&fix).uniq, subjects.map { |subject| subject.merge("article" => subject["article"] && fix.call(subject["article"])) },
          dropped ]
      rescue Media::Error => e
        Rails.logger.warn("Could not check research article titles: #{e.message}")
        [ articles, subjects, [] ]
      end
  end
end
