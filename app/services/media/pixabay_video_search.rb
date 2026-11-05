module Media
  # Searches Pixabay for video: modern footage of real places (a coast, a city, a valley from the air)
  # and moods (a stormy sea, clouds). Needs PIXABAY_API_KEY (free account).
  #
  # Pixabay matches words loosely ("Boston harbour" returns Hong Kong's harbour), so a clip is kept only
  # when its tags hold every telling word of the query. AI-generated clips are left out: the video
  # shows real footage only.
  class PixabayVideoSearch
    ENDPOINT = "https://pixabay.com/api/videos/".freeze
    PROVIDER = "pixabay".freeze
    LICENSE = PixabaySearch::LICENSE
    # Largest first, up to the render's 1080p.
    SIZES = %w[large medium small].freeze
    MAX_HEIGHT = 1080
    MIN_HEIGHT = 540
    MIN_SECONDS = 4
    FETCHED = 20
    STOPWORDS = %w[the and with from into over aerial view footage video clip shot drone timelapse time lapse].freeze

    def initialize(api_key:, http: HttpJson)
      @api_key = api_key
      @http = http
    end

    def search(query, limit: 2)
      data = @http.get(ENDPOINT, key: @api_key, q: query, safesearch: true, per_page: FETCHED)
      wanted = self.class.words(query)
      return [] if wanted.empty?

      Array(data["hits"]).filter_map do |hit|
        next if hit["isAiGenerated"] || hit["duration"].to_i < MIN_SECONDS
        next unless (wanted - self.class.words(hit["tags"])).empty?

        to_result(hit)
      end.first(limit)
    end

    # Words of 4+ letters compared on their first 5 letters ("harbours" ~ "harbour"), without filler.
    def self.words(text)
      text.to_s.downcase.scan(/[[:alpha:]]{4,}/).reject { |word| STOPWORDS.include?(word) }.map { |word| word.first(5) }.uniq
    end

    private
      def to_result(hit)
        file = SIZES.filter_map { |size| hit.dig("videos", size) }
                    .find { |video| video["url"].present? && video["height"].to_i.between?(MIN_HEIGHT, MAX_HEIGHT) }
        return unless file

        VideoResult.new(provider: PROVIDER, title: hit["tags"].to_s, video_url: file["url"], poster_url: file["thumbnail"],
                        page_url: hit["pageURL"], credit: "#{hit["user"]} on Pixabay", license: LICENSE,
                        duration_ms: hit["duration"].to_i * 1000, description: "Pixabay footage: #{hit["tags"]}")
      end
  end
end
