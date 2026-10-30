module Media
  # The images used in an English Wikipedia article: editors have already picked them for the
  # subject, so they are far more on-topic than a keyword search across all of Commons (searching
  # "HMS Calypso" returns the wrong ships; the article "HMS Calypso (D61)" shows the right one).
  # One call per article to en.wikipedia.org (commons.wikimedia.org is blocked on some networks).
  class WikipediaArticleImages
    ENDPOINT = CommonsSearch::METADATA_ENDPOINT
    PROVIDER = "wikipedia_article".freeze
    MAX_IMAGES = 50
    # Articles include icons and badges; real pictures are at least this big on their short side.
    MIN_SHORT_SIDE = 400
    SKIP_TITLES = /logo|icon|flag|coat of arms|signature|seal|map icon/i

    def initialize(http: HttpJson)
      @http = http
    end

    # ImageResults for the article's usable, freely licensed pictures. An article that doesn't exist
    # returns none.
    def images(article)
      data = @http.get(ENDPOINT,
        action: "query", generator: "images", titles: article, gimlimit: MAX_IMAGES, redirects: 1,
        prop: "imageinfo", iiprop: "url|size|mime|extmetadata", iiurlwidth: 1600, format: "json", formatversion: 2)

      Array(data.dig("query", "pages")).filter_map do |page|
        next if page["title"].to_s.match?(SKIP_TITLES) || self.class.too_small?(page)

        CommonsSearch.result_from(page, provider: PROVIDER, source_article: article)
      end
    end

    def self.too_small?(page)
      info = Array(page["imageinfo"]).first || {}
      [ info["width"].to_i, info["height"].to_i ].min < MIN_SHORT_SIDE
    end
  end
end
