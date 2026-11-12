module Media
  # The pictures in a Wikipedia article's Commons category and its subcategories: the folder Commons
  # editors keep for exactly that subject. It is usually much bigger than the article's own pictures
  # ("Great Molasses Flood" shows 6; its category holds 24, with the city archive's photos of the
  # wreckage). The category comes from the article's Wikidata item (property P373). The search runs
  # through api.wikimedia.org with deepcategory:, since commons.wikimedia.org is blocked on some networks.
  #
  # Also the photos tagged on Commons as depicting the article's subject (structured data, P180):
  # that exact person, ship or place, whatever the file is named or wherever it is filed.
  class CommonsCategoryImages
    PROVIDER = "commons_category".freeze
    DEPICTS_PROVIDER = "commons_depicts".freeze
    WIKIDATA_ENDPOINT = "https://www.wikidata.org/w/api.php".freeze
    COMMONS_CATEGORY = "P373".freeze
    DEPICTS = "P180".freeze
    MAX_IMAGES = 40

    def initialize(http: HttpJson)
      @http = http
      @items = {}
      @categories = {}
    end

    # ImageResults for the photos depicting the subject, then the category's, freely licensed and
    # credited to the article. An article without a Wikidata item returns none.
    def images(article)
      (depicted(article) + category_images(article)).uniq(&:image_url)
    end

    # The search for the category's videos, or nil when the article has no category.
    def video_query(article)
      name = category(article)
      name && %(deepcategory:"#{name}")
    end

    # The article's Commons category name, looked up once per article.
    def category(article)
      @categories.fetch(article) { @categories[article] = category_lookup(article) }
    end

    # The article's Wikidata item id ("Q40026"), looked up once per article.
    def item(article)
      @items.fetch(article) { @items[article] = item_lookup(article) }
    end

    private
      def depicted(article)
        id = item(article)
        return [] unless id

        results(file_titles("haswbstatement:#{DEPICTS}=#{id} filetype:bitmap"), DEPICTS_PROVIDER, article)
      end

      def category_images(article)
        name = category(article)
        return [] unless name

        titles = file_titles(%(deepcategory:"#{name}" filetype:bitmap))
        # deepcategory gives up on very large category trees; the category's own files still help.
        titles = file_titles(%(incategory:"#{name}" filetype:bitmap)) if titles.empty?
        results(titles, PROVIDER, article)
      end

      def results(titles, provider, article)
        return [] if titles.empty?

        CommonsSearch.new(http: @http).metadata_pages(titles).filter_map do |page|
          next if page["title"].to_s.match?(WikipediaArticleImages::SKIP_TITLES) || WikipediaArticleImages.too_small?(page)

          CommonsSearch.result_from(page, provider: provider, source_article: article)
        end
      end

      def item_lookup(article)
        pages = @http.get(CommonsSearch::METADATA_ENDPOINT, action: "query", titles: article, redirects: 1, prop: "pageprops",
                                                            ppprop: "wikibase_item", format: "json", formatversion: 2)
        Array(pages.dig("query", "pages")).first&.dig("pageprops", "wikibase_item")
      end

      def category_lookup(article)
        id = item(article)
        return unless id

        entity = @http.get(WIKIDATA_ENDPOINT, action: "wbgetentities", ids: id, props: "claims", format: "json")
        entity.dig("entities", id, "claims", COMMONS_CATEGORY, 0, "mainsnak", "datavalue", "value").presence
      end

      def file_titles(query)
        data = @http.get(CommonsSearch::SEARCH_ENDPOINT, q: query, limit: MAX_IMAGES)
        Array(data["pages"]).map { |page| page["title"].to_s }.select { |title| title.start_with?("File:") }.uniq
      end
  end
end
