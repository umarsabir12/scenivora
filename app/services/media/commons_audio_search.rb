module Media
  # Searches Wikimedia Commons for freely licensed music. Same endpoints and license rules as
  # CommonsSearch; keeps tracks between 1 and 15 minutes long and under 40 MB.
  class CommonsAudioSearch
    PROVIDER = "wikimedia_commons".freeze
    MIN_SECONDS = 60
    MAX_SECONDS = 15 * 60
    MAX_BYTES = 40.megabytes
    CANDIDATE_MULTIPLIER = 4

    def initialize(http: HttpJson)
      @http = http
    end

    def search(query, limit: 8)
      data = @http.get(CommonsSearch::SEARCH_ENDPOINT, q: "#{query} filetype:audio",
                       limit: [ limit * CANDIDATE_MULTIPLIER, CommonsSearch::MAX_SEARCH_RESULTS ].min)
      titles = Array(data["pages"]).map { |page| page["title"].to_s }.select { |title| title.start_with?("File:") }.uniq
      return [] if titles.empty?

      metadata = @http.get(CommonsSearch::METADATA_ENDPOINT,
        action: "query", titles: titles.first(CommonsSearch::MAX_TITLES_PER_REQUEST).join("|"), prop: "imageinfo",
        iiprop: "url|size|mime|extmetadata", format: "json", formatversion: 2)
      Array(metadata.dig("query", "pages")).filter_map { |page| to_result(page) }.first(limit)
    end

    private
      def to_result(page)
        info = Array(page["imageinfo"]).first
        return unless info && audio?(info["mime"].to_s)
        return unless info["duration"].to_f.between?(MIN_SECONDS, MAX_SECONDS) && info["size"].to_i <= MAX_BYTES

        meta = info["extmetadata"] || {}
        license = meta.dig("LicenseShortName", "value").to_s
        return unless license.match?(CommonsSearch::ALLOWED_LICENSE)

        AudioResult.new(
          provider: PROVIDER,
          title: page["title"].to_s.delete_prefix("File:").sub(/\.[a-z0-9]+\z/i, ""),
          audio_url: info["url"],
          page_url: info["descriptionurl"],
          credit: ActionController::Base.helpers.strip_tags(meta.dig("Artist", "value").to_s).squish.presence || "Wikimedia Commons contributor",
          license: license,
          duration_ms: (info["duration"].to_f * 1000).round,
          content_type: info["mime"]
        )
      end

      def audio?(mime)
        mime.start_with?("audio/") || mime == "application/ogg"
      end
  end
end
