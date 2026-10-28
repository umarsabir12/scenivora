module Media
  # One candidate image from a free source, with what we need to show, check and credit it.
  # description, taken_on and categories are optional: not every source provides them.
  ImageResult = Data.define(:provider, :image_url, :page_url, :credit, :license, :description, :taken_on, :categories) do
    def initialize(description: nil, taken_on: nil, categories: nil, **rest)
      super
    end
  end
end
