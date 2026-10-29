module Media
  # Checks article titles against English Wikipedia in one free request, following redirects, so a
  # title a model invented or misspelled never reaches the picture search.
  class WikipediaTitles
    ENDPOINT = CommonsSearch::METADATA_ENDPOINT
    MAX_TITLES_PER_REQUEST = 50

    def initialize(http: HttpJson)
      @http = http
    end

    # Returns { given title => the article's real title, or nil when there is no such article }.
    def resolve(titles)
      titles = Array(titles).map { |title| title.to_s.squish }.reject(&:empty?).uniq
      return {} if titles.empty?

      data = @http.get(ENDPOINT, action: "query", titles: titles.first(MAX_TITLES_PER_REQUEST).join("|"), redirects: 1,
                                 format: "json", formatversion: 2)
      query = data["query"] || {}
      renames = (Array(query["normalized"]) + Array(query["redirects"])).to_h { |step| [ step["from"], step["to"] ] }
      existing = Array(query["pages"]).reject { |page| page["missing"] || page["invalid"] }.map { |page| page["title"] }

      titles.to_h do |title|
        final = title
        3.times { final = renames.fetch(final, final) } # normalised, then redirected
        [ title, existing.include?(final) ? final : nil ]
      end
    end
  end
end
