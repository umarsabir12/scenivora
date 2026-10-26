module Media
  # Searches Wikimedia Commons for freely licensed photos. No API key is needed.
  #
  # Uses the Wikimedia endpoints that are reachable from restricted networks:
  # search via api.wikimedia.org, metadata and license via en.wikipedia.org, and files
  # from upload.wikimedia.org (the URLs returned by the metadata call).
  class CommonsSearch
    SEARCH_ENDPOINT = "https://api.wikimedia.org/core/v1/commons/search/page".freeze
    METADATA_ENDPOINT = "https://en.wikipedia.org/w/api.php".freeze
    PROVIDER = "wikimedia_commons".freeze
    PHOTO_TYPES = %w[image/jpeg image/png image/webp].freeze
    # Only licenses that allow reuse in a monetised video with attribution (or none needed).
    ALLOWED_LICENSE = /\A(Public domain|CC0( 1\.0)?|CC BY(-SA)?( \d\.\d)?)\z/i
    CANDIDATE_MULTIPLIER = 4
    MAX_SEARCH_RESULTS = 100
    MAX_TITLES_PER_REQUEST = 50

    def initialize(http: HttpJson)
      @http = http
    end

    def search(query, limit: 3)
      titles = file_titles(query, limit * CANDIDATE_MULTIPLIER)
      return [] if titles.empty?

      metadata_pages(titles).filter_map { |page| to_result(page) }.first(limit)
    end

    private
      def file_titles(query, limit)
        data = @http.get(SEARCH_ENDPOINT, q: "#{query} filetype:bitmap", limit: [ limit, MAX_SEARCH_RESULTS ].min)
        Array(data["pages"]).map { |page| page["title"].to_s }.select { |title| title.start_with?("File:") }.uniq
      end

      def metadata_pages(titles)
        data = @http.get(METADATA_ENDPOINT,
          action: "query", titles: titles.first(MAX_TITLES_PER_REQUEST).join("|"), prop: "imageinfo",
          iiprop: "url|size|mime|extmetadata", iiurlwidth: 1600, format: "json", formatversion: 2)
        Array(data.dig("query", "pages"))
      end

      def to_result(page)
        info = Array(page["imageinfo"]).first
        return unless info && PHOTO_TYPES.include?(info["mime"])

        meta = info["extmetadata"] || {}
        license = meta.dig("LicenseShortName", "value").to_s
        return unless license.match?(ALLOWED_LICENSE)

        ImageResult.new(
          provider: PROVIDER,
          image_url: info["thumburl"] || info["url"],
          page_url: info["descriptionurl"],
          credit: plain_text(meta.dig("Artist", "value")).presence || "Wikimedia Commons contributor",
          license: license
        )
      end

      # Commons metadata is HTML; keep the readable text only.
      def plain_text(html)
        ActionController::Base.helpers.strip_tags(html.to_s).squish
      end
  end
end
