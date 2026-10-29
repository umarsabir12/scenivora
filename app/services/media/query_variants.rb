module Media
  # Turns planner queries into an ordered list of searches, from specific to broad.
  #
  # Wikimedia's search matches every word, so a precise query often finds nothing and simpler forms
  # help. But a form that loses the subject ("Prince", "Corfu") finds unrelated files, so every
  # broader form keeps the main subject's name and at least 2 words. Years stay, because they
  # separate an archive photo from a modern one; one form without the year comes last.
  module QueryVariants
    YEARS = /\A\d{3,4}s?\z/
    FILLER = %w[a an the of in on at to for and with from by].freeze
    # Lower-case words that belong inside a name: "Battle of Yarmouk", "Khalid ibn al-Walid".
    NAME_JOINERS = %w[of de da del der van von bin ibn al].freeze
    MIN_WORDS = 2

    # topic: the project's prompt. Its main name is the subject when the first query uses it or names
    # nobody; otherwise the first query's leading name is.
    def self.for(queries, limit:, topic: nil)
      originals = Array(queries).map { |query| query.to_s.squish }.reject(&:empty?)
      subject = subject_for(originals.first, topic)
      simpler = originals.flat_map { |query| broader_forms(query, subject) }
      without_year = originals.find { |query| query.split.any? { |word| word.match?(YEARS) } }

      variants = originals + simpler + [ without_year && with_subject(content_words(without_year), subject, []) ].compact
      variants.uniq { |query| query.downcase }.reject { |query| query.split.size < MIN_WORDS }.first(limit)
    end

    # The names in the query, then trailing parts dropped one at a time, each with the query's years.
    # A part is a whole name ("William Gorgas") or one plain word, so no name is cut in half. The
    # subject is added back to every form, and a query that names it can shrink to just the subject.
    def self.broader_forms(query, subject)
      words = content_words(query)
      years = query.split.select { |word| word.match?(YEARS) }
      names = words.select { |word| word.match?(/\A[[:upper:]]/) }
      subject_words = subject.to_s.split
      rest = words.reject { |word| subject_words.any? { |own| own.casecmp?(word) } }
      parts = rest.chunk_while { |a, b| a.match?(/\A[[:upper:]]/) && b.match?(/\A[[:upper:]]/) }.to_a
      smallest = rest.size < words.size ? 0 : 1
      drops = (parts.size - 1).downto(smallest).map { |count| parts.first(count).flatten }
      ([ names ].reject(&:empty?) + drops).map { |form| with_subject(form, subject, years) }
    end

    def self.subject_for(first_query, topic)
      topic_name = subject_of(topic.to_s.split(":").first)
      query_name = subject_of(first_query)
      return topic_name if query_name.empty? || (topic_name.present? && first_query.downcase.include?(topic_name.downcase))

      query_name
    end

    # The first run of capitalised words, e.g. "Prince Philip" in "Prince Philip: the baby...".
    def self.subject_of(text)
      run = []
      text.to_s.split.each do |word|
        clean = word.delete(",.;:!?\"'()")
        if clean.match?(/\A([[:lower:]]+-)?[[:upper:]]/) && !FILLER.include?(clean.downcase)
          run << clean
        elsif run.any? && NAME_JOINERS.include?(clean.downcase)
          run << clean
        elsif run.any?
          break
        end
      end
      run.pop while run.any? && NAME_JOINERS.include?(run.last.downcase)
      run.join(" ")
    end

    def self.content_words(query)
      query.split.reject { |word| word.match?(YEARS) || FILLER.include?(word.downcase) }
    end

    # Puts the subject's name in front unless the form already has all of it.
    def self.with_subject(words, subject, years)
      subject_words = subject.to_s.split
      missing = subject_words.any? { |word| words.none? { |own| own.casecmp?(word) } }
      words = subject_words + words.reject { |word| subject_words.any? { |own| own.casecmp?(word) } } if missing
      (words + years).join(" ")
    end
  end
end
