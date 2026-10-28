module Media
  # Searches Wikimedia Commons for freely licensed video, mostly archival footage. Same endpoints
  # and license rules as CommonsSearch. Picks a web-friendly transcode no taller than 720p.
  class CommonsVideoSearch
    PROVIDER = "wikimedia_commons".freeze
    MIN_SECONDS = 3
    MIN_HEIGHT = 360 # 240p archive transcodes look like mush at 1080p
    MAX_HEIGHT = 720
    CANDIDATE_MULTIPLIER = 3

    def initialize(http: HttpJson)
      @http = http
    end

    def search(query, limit: 2)
      data = @http.get(CommonsSearch::SEARCH_ENDPOINT, q: "#{query} filetype:video",
                       limit: [ limit * CANDIDATE_MULTIPLIER, CommonsSearch::MAX_SEARCH_RESULTS ].min)
      titles = Array(data["pages"]).map { |page| page["title"].to_s }.select { |title| title.start_with?("File:") }.uniq
      return [] if titles.empty?

      metadata = @http.get(CommonsSearch::METADATA_ENDPOINT,
        action: "query", titles: titles.first(CommonsSearch::MAX_TITLES_PER_REQUEST).join("|"), prop: "videoinfo",
        viprop: "url|size|mime|derivatives|extmetadata", viurlwidth: 640, format: "json", formatversion: 2)
      Array(metadata.dig("query", "pages")).filter_map { |page| to_result(page) }.first(limit)
    end

    private
      def to_result(page)
        info = Array(page["videoinfo"]).first
        return unless info && video?(info) && info["duration"].to_f >= MIN_SECONDS
        url, height = playable(info)
        return if height < MIN_HEIGHT

        meta = info["extmetadata"] || {}
        license = meta.dig("LicenseShortName", "value").to_s
        return unless license.match?(CommonsSearch::ALLOWED_LICENSE)

        VideoResult.new(
          provider: PROVIDER,
          title: page["title"].to_s.delete_prefix("File:").sub(/\.[a-z0-9]+\z/i, ""),
          video_url: url,
          poster_url: info["thumburl"],
          page_url: info["descriptionurl"],
          credit: ActionController::Base.helpers.strip_tags(meta.dig("Artist", "value").to_s).squish.presence || "Wikimedia Commons contributor",
          license: license,
          duration_ms: (info["duration"].to_f * 1000).round,
          **CommonsMetadata.details(meta)
        )
      end

      def video?(info)
        info["mime"].to_s.start_with?("video/") ||
          (info["mime"] == "application/ogg" && info["width"].to_i.positive?)
      end

      # [url, height] of the tallest WebM up to 720p, preferring Wikimedia's transcodes over the
      # original upload at the same height (smaller, and they seek quickly). Falls back to the
      # original file at its own height.
      def playable(info)
        webm = Array(info["derivatives"]).select do |derivative|
          derivative["type"].to_s.start_with?("video/webm") && derivative["height"].to_i.between?(1, MAX_HEIGHT)
        end
        best = webm.max_by { |derivative| [ derivative["height"].to_i, derivative["src"].to_s.include?("/transcoded/") ? 1 : 0 ] }
        best ? [ best["src"], best["height"].to_i ] : [ info["url"], info["height"].to_i ]
      end
  end
end
