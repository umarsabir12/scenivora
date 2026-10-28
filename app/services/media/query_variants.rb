module Media
  # Turns planner queries into an ordered list of searches, from specific to broad.
  #
  # Wikimedia's search matches every word, so a precise query like "Karachi 1876" often finds
  # nothing while "Karachi" finds plenty. After the planner's own queries come simpler forms of
  # each: just the names in it, then without years and filler words, then with trailing words
  # dropped one at a time.
  module QueryVariants
    YEARS = /\b\d{3,4}s?\b/
    FILLER = %w[a an the of in on at to for and with from by].freeze

    def self.for(queries, limit:)
      originals = Array(queries).map { |query| query.to_s.squish }.reject(&:empty?)
      simpler = originals.flat_map { |query| broader_forms(query) }

      (originals + simpler).uniq { |query| query.downcase }.first(limit)
    end

    # Names first (capitalised words keep the subject), then trailing words dropped one at a time.
    def self.broader_forms(query)
      words = query.gsub(YEARS, " ").split.reject { |word| FILLER.include?(word.downcase) }
      names = words.select { |word| word.match?(/\A[[:upper:]]/) }
      [ names.join(" ") ].reject(&:empty?) + words.size.downto(1).map { |count| words.first(count).join(" ") }
    end
  end
end
