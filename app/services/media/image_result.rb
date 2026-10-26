module Media
  # One candidate image from a free source, with what we need to show and credit it.
  ImageResult = Data.define(:provider, :image_url, :page_url, :credit, :license)
end
