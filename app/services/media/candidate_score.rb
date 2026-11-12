module Media
  # Scores a scene's candidate pictures in code, from what Wikimedia says about each one (file name,
  # categories, description, date, the article it came from), so only the few that fit go on to the
  # paid picture check. Higher is better; a candidate below MIN_SCORE isn't worth a look.
  class CandidateScore
    MIN_SCORE = 6.0
    MIN_WORD = 3
    STOPWORDS = (ArticleLibrary::STOPWORDS + Scene::STOPWORDS + %w[jpg jpeg png webp tif tiff svg]).to_set.freeze
    # How much a word counts, by where the scene uses it: its search terms and the names in its
    # narration say what it shows; the visual intent adds detail.
    WEIGHTS = { query: 2.0, name: 2.0, intent: 1.0 }.freeze
    # Words in most of the video's pictures (usually the topic's own name) say little about a scene.
    COMMON_WEIGHT = 0.25
    # Where the word is found in the candidate: a file name is written about the picture itself.
    FIELDS = { title: 1.5, categories: 1.0, description: 1.0 }.freeze
    MAX_WORD_POINTS = 9.0
    OWN_ARTICLE = { first: 2.5, other: 1.5 }.freeze
    # Commons says the picture depicts the subject of one of the scene's articles: that exact person,
    # ship or place, whatever the file is named. With its own article it reaches MIN_SCORE by itself;
    # a photo from decades later still loses its late penalty.
    DEPICTS_POINTS = 3.5
    YEAR_POINTS = { 3 => 3.0, 10 => 1.0 }.freeze
    # A photo taken long after the moment shows something else: a modern street, a reunion. A later
    # portrait still introduces a person, so it loses little; nothing is lost when the scene speaks of today.
    LATE_YEARS = 20
    LATE_PENALTY = { "historical_event" => 4.0, "object" => 3.0, "real_place" => 3.0, "real_person" => 1.0 }.freeze
    DEFAULT_LATE_PENALTY = 2.0
    PRESENT_DAY = /\b(today|now|nowadays|present|modern|still stands?|remains?|later became)\b/i
    # Pictures that are rarely what a scene shows, unless the scene asks for one.
    OFF_KINDS = %w[map diagram chart graph logo stamp coin banknote signature seal flag grave tomb plaque
                   marker poster cover album screenshot].freeze
    OFF_KIND_PENALTY = 3.0
    # The plan names this very file ("the BostonMolassesDisaster image from Great Molasses Flood").
    NAMED_FILE_POINTS = 4.0
    MIN_NAMED_TITLE = 8
    YEAR = /(?<!\d)(1[5-9]\d\d|20[0-3]\d)(?!\d)/

    # common_words: stems found in much of the video's library (see ArticleLibrary#common_words).
    def initialize(scene, common_words: [])
      @scene = scene
      @plan = scene.plan || {}
      @common = common_words.to_set
      @wanted = wanted_words
      @years = scene_years
      @articles = Array(@plan["articles"]).map { |article| article.to_s.squish }
      @plan_text = self.class.series_key_text([ @plan["visual_intent"], *@plan["search_queries"] ].join(" "))
    end

    def call(candidate)
      fields = candidate_fields(candidate)
      word_points(fields) + article_points(candidate) + year_points(candidate) + named_file_points(candidate) -
        off_kind_penalty(fields)
    end

    # The candidates worth checking, best first: scored at least MIN_SCORE, no two near-copies of the
    # same picture (a series of aerial shots counts once).
    def best(candidates, limit:)
      scored = candidates.map { |candidate| [ candidate, call(candidate) ] }.select { |_, score| score >= MIN_SCORE }
      ranked = scored.each_with_index.sort_by { |(_, score), index| [ -score, index ] }.map { |(candidate, _), _| candidate }
      ranked.uniq { |candidate| self.class.series_key(candidate) }.first(limit)
    end

    # A file name without its numbers, so "Old_Corfu_town_aerial_01" and "_02" are one picture.
    def self.series_key(candidate)
      series_key_text(title_of(candidate))
    end

    def self.series_key_text(text)
      text.to_s.downcase.gsub(/[^[:alpha:]]+/, " ").squish
    end

    def self.title_of(candidate)
      CGI.unescape(candidate.page_url.to_s[/File:(.+)\z/, 1].to_s).tr("_", " ").sub(/\.\w+\z/, "")
    end

    def self.words(text)
      CGI.unescape(text.to_s).downcase.scan(/[[:alpha:]]{#{MIN_WORD},}/).reject { |word| STOPWORDS.include?(word) }
         .map { |word| word.first(5) }.uniq
    end

    private
      # stem => weight: the best weight the scene gives the word.
      def wanted_words
        sources = {
          query: [ @scene.search_query, *@plan["search_queries"] ].compact_blank.join(" "),
          name: @scene.text.to_s.scan(/\b[[:upper:]][[:alpha:]'’-]+(?:\s+(?:of|de|the|al|ibn|bin|von|van)?\s*[[:upper:]][[:alpha:]'’-]+)*/).join(" "),
          intent: @plan["visual_intent"].to_s
        }
        sources.each_with_object({}) do |(source, text), wanted|
          self.class.words(text).each do |word|
            weight = WEIGHTS.fetch(source) * (@common.include?(word) ? COMMON_WEIGHT : 1)
            wanted[word] = [ wanted.fetch(word, 0), weight ].max
          end
        end
      end

      def candidate_fields(candidate)
        { title: self.class.words(self.class.title_of(candidate)), categories: self.class.words(candidate.categories),
          description: self.class.words(candidate.description) }
      end

      def word_points(fields)
        points = @wanted.sum do |word, weight|
          best = FIELDS.filter_map { |field, factor| factor if fields[field].include?(word) }.max
          best ? weight * best : 0
        end
        [ points, MAX_WORD_POINTS ].min
      end

      def article_points(candidate)
        index = @articles.index(candidate.source_article.to_s.squish)
        return 0 unless index

        points = index.zero? ? OWN_ARTICLE[:first] : OWN_ARTICLE[:other]
        candidate.provider == CommonsCategoryImages::DEPICTS_PROVIDER ? points + DEPICTS_POINTS : points
      end

      def named_file_points(candidate)
        key = self.class.series_key(candidate)
        key.length >= MIN_NAMED_TITLE && " #{@plan_text} ".include?(" #{key} ") ? NAMED_FILE_POINTS : 0
      end

      def year_points(candidate)
        year = candidate_year(candidate)
        return 0 if @years.empty? || year.nil?

        gap = @years.map { |wanted| (year - wanted).abs }.min
        close = YEAR_POINTS.find { |within, _| gap <= within }
        return close.last if close
        if year > @years.max + LATE_YEARS && !@scene.text.to_s.match?(PRESENT_DAY)
          return -LATE_PENALTY.fetch(@plan["subject_type"], DEFAULT_LATE_PENALTY)
        end

        0
      end

      # When the picture was made: its recorded date, else a year in its name, categories or description.
      def candidate_year(candidate)
        [ candidate.taken_on, self.class.title_of(candidate), candidate.description, candidate.categories ].each do |text|
          year = text.to_s[YEAR, 1]
          return year.to_i if year
        end
        nil
      end

      def scene_years
        [ @scene.text, @scene.search_query, *@plan["search_queries"], @plan["visual_intent"] ].join(" ")
          .scan(YEAR).flatten.map(&:to_i).uniq
      end

      def off_kind_penalty(fields)
        named = (fields[:title] + fields[:categories]).to_set
        asked = @wanted.keys.to_set
        OFF_KINDS.any? { |kind| stem = kind.first(5); named.include?(stem) && !asked.include?(stem) } ? OFF_KIND_PENALTY : 0
      end
  end
end
