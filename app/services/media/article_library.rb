module Media
  # A video's own picture library: the images from every Wikipedia article the planner named, fetched
  # once and shared by all scenes, so a perfect photo found for one scene can serve another.
  class ArticleLibrary
    MAX_ITEMS = 60
    MIN_WORD = 4
    # A word found in more than this share of the library (usually the subject's own name) matches
    # almost every picture, so it says nothing about which picture fits a scene.
    COMMON_SHARE = 0.25
    STOPWORDS = %w[with that this from into over under about after before were they them their there
                   what when where which while have been being will would could should very also just
                   than then some such each every many much only still here file photo image picture].freeze

    # article title => [ImageResult]
    attr_reader :by_article

    def self.build(articles, fetcher: WikipediaArticleImages.new, limit: MAX_ITEMS)
      by_article = {}
      seen = Set.new
      articles.compact_blank.map(&:squish).uniq.each do |article|
        results = fetcher.images(article)
        Rails.logger.info("Wikipedia article #{article.inspect} has no usable pictures or doesn't exist") if results.empty?
        by_article[article] = results.reject { |result| seen.include?(result.image_url) }.each { |result| seen << result.image_url }
      rescue Media::Error => e
        Rails.logger.warn("Wikipedia article #{article.inspect} could not be read: #{e.message}")
      end
      new(by_article, limit: limit)
    end

    def initialize(by_article, limit: MAX_ITEMS)
      @by_article = by_article
      @items = by_article.values.flatten.first(limit)
    end

    def items
      @items
    end

    def empty?
      @items.empty?
    end

    # The pictures from these articles, in the order given.
    def for_articles(articles)
      Array(articles).flat_map { |article| @by_article.fetch(article.to_s.squish, []) } & @items
    end

    # Library pictures whose title, description or categories share a telling word with the text, the
    # ones sharing the most words first.
    def matching(text)
      wanted = words(text) - common_words
      return [] if wanted.empty?

      scored = @items.map { |item| [ item, (item_words(item) & wanted).size ] }.select { |_, score| score.positive? }
      scored.each_with_index.sort_by { |(_, score), index| [ -score, index ] }.map { |(item, _), _| item }
    end

    private
      def item_words(item)
        @item_words ||= {}
        @item_words[item.image_url] ||= words([ item.page_url.to_s[/File:(.+)\z/, 1].to_s.tr("_", " "), item.description,
                                                item.categories ].join(" "))
      end

      def common_words
        @common_words ||= begin
          counts = @items.flat_map { |item| item_words(item) }.tally
          limit = [ 2, (@items.size * COMMON_SHARE).floor ].max
          counts.select { |_, count| count > limit }.keys
        end
      end

      # Lower-cased words of 4+ letters, compared on their first 5 letters ("flights" ~ "flight").
      def words(text)
        CGI.unescape(text.to_s).downcase.scan(/[[:alpha:]]{#{MIN_WORD},}/).reject { |word| STOPWORDS.include?(word) }.map { |word| word.first(5) }.uniq
      end
  end
end
