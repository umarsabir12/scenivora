module Media
  # Searches Pixabay for photos. Needs PIXABAY_API_KEY (free account).
  class PixabaySearch
    ENDPOINT = "https://pixabay.com/api/".freeze
    PROVIDER = "pixabay".freeze
    LICENSE = "Pixabay Content License".freeze

    def initialize(api_key:, http: HttpJson)
      @api_key = api_key
      @http = http
    end

    def search(query, limit: 3)
      data = @http.get(ENDPOINT,
        key: @api_key, q: query, image_type: "photo", safesearch: true, per_page: [ limit, 3 ].max)

      Array(data["hits"]).first(limit).map do |hit|
        ImageResult.new(
          provider: PROVIDER,
          image_url: hit["webformatURL"],
          page_url: hit["pageURL"],
          credit: "#{hit["user"]} on Pixabay",
          license: LICENSE
        )
      end
    end
  end
end
