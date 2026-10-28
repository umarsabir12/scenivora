module Media
  # One candidate video clip from a free source, with what we need to cut, check, show and credit it.
  VideoResult = Data.define(:provider, :title, :video_url, :poster_url, :page_url, :credit, :license, :duration_ms,
                            :description, :taken_on, :categories) do
    def initialize(description: nil, taken_on: nil, categories: nil, **rest)
      super
    end
  end
end
