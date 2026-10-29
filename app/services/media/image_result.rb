module Media
  # One candidate image from a free source, with what we need to show, check and credit it.
  # description, taken_on and categories are optional: not every source provides them.
  # source_article: the Wikipedia article the picture came from, when it came from one.
  ImageResult = Data.define(:provider, :image_url, :page_url, :credit, :license, :description, :taken_on, :categories,
                            :source_article) do
    def initialize(description: nil, taken_on: nil, categories: nil, source_article: nil, **rest)
      super
    end
  end
end
