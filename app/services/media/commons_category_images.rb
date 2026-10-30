module Media
  # The pictures in a Wikipedia article's Commons category and its subcategories: the folder Commons
  # editors keep for exactly that subject. It is usually much bigger than the article's own pictures
  # ("Great Molasses Flood" shows 6; its category holds 24, with the city archive's photos of the
  # wreckage). The category comes from the article's Wikidata item (property P373). The search runs
  # through api.wikimedia.org with deepcategory:, since commons.wikimedia.org is blocked on some networks.
  class CommonsCategoryImages
    PROVIDER = "commons_category".freeze
    WIKIDATA_ENDPOINT = "https://www.wikidata.org/w/api.php".freeze
    COMMONS_CATEGORY = "P373".freeze
    MAX_IMAGES = 40

    def initialize(http: HttpJson)
      @http = http
      @categories = {}
    end

    # ImageResults for the category's freely licensed photos, credited to the article. An article
    # without a Commons category returns none.
    def images(article)
      name = category(article)
      return [] unless name

      titles = file_titles(%(deepcategory:"#{name}" filetype:bitmap))
      # deepcategory gives up on very large category trees; the category's own files still help.
      titles = file_titles(%(incategory:"#{name}" filetype:bitmap)) if titles.empty?
      return [] if titles.empty?

      CommonsSearch.new(http: @http).metadata_pages(titles).filter_map do |page|
        next if page["title"].to_s.match?(WikipediaArticleImages::SKIP_TITLES) || WikipediaArticleImages.too_small?(page)

        CommonsSearch.result_from(page, provider: PROVIDER, source_article: article)
      end
    end

    # The search for the category's videos, or nil when the article has no category.
    def video_query(article)
      name = category(article)
      name && %(deepcategory:"#{name}")
    end

    # The article's Commons category name, looked up once per article.
    def category(article)
      @categories.fetch(article) { @categories[article] = lookup(article) }
    end

    private
      def lookup(article)
        pages = @http.get(CommonsSearch::METADATA_ENDPOINT, action: "query", titles: article, redirects: 1, prop: "pageprops",
                                                            ppprop: "wikibase_item", format: "json", formatversion: 2)
        item = Array(pages.dig("query", "pages")).first&.dig("pageprops", "wikibase_item")
        return unless item

        entity = @http.get(WIKIDATA_ENDPOINT, action: "wbgetentities", ids: item, props: "claims", format: "json")
        entity.dig("entities", item, "claims", COMMONS_CATEGORY, 0, "mainsnak", "datavalue", "value").presence
      end

      def file_titles(query)
        data = @http.get(CommonsSearch::SEARCH_ENDPOINT, q: query, limit: MAX_IMAGES)
        Array(data["pages"]).map { |page| page["title"].to_s }.select { |title| title.start_with?("File:") }.uniq
      end
  end
end
