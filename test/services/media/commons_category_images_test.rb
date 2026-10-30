require "test_helper"

class Media::CommonsCategoryImagesTest < ActiveSupport::TestCase
  # Answers each endpoint the way Wikipedia, Wikidata and the Commons search do.
  class FakeHttp
    attr_reader :calls

    def initialize(item: "Q1", category: "Boston Molasses Disaster", deep: [ "File:Wreckage 1919.jpg", "File:Logo.jpg" ], shallow: [])
      @item = item
      @category = category
      @deep = deep
      @shallow = shallow
      @calls = []
    end

    def get(url, params = {})
      @calls << [ url, params ]
      if url == Media::CommonsCategoryImages::WIKIDATA_ENDPOINT
        claims = @category ? { "P373" => [ { "mainsnak" => { "datavalue" => { "value" => @category } } } ] } : {}
        { "entities" => { @item => { "claims" => claims } } }
      elsif url == Media::CommonsSearch::SEARCH_ENDPOINT
        titles = params[:q].start_with?("deepcategory:") ? @deep : @shallow
        { "pages" => titles.map { |title| { "title" => title } } }
      elsif params[:prop] == "pageprops"
        { "query" => { "pages" => [ { "title" => params[:titles], "pageprops" => (@item ? { "wikibase_item" => @item } : {}) } ] } }
      else
        { "query" => { "pages" => params[:titles].split("|").map { |title| page(title) } } }
      end
    end

    def page(title)
      { "title" => title, "imageinfo" => [ {
        "mime" => "image/jpeg", "width" => 1600, "height" => 1200,
        "thumburl" => "https://upload.wikimedia.org/#{title.parameterize}.jpg",
        "descriptionurl" => "https://commons.wikimedia.org/wiki/#{title.tr(' ', '_')}",
        "extmetadata" => { "Artist" => { "value" => "City of Boston Archives" }, "LicenseShortName" => { "value" => "Public domain" } }
      } ] }
    end

    def searches
      @calls.select { |url, _| url == Media::CommonsSearch::SEARCH_ENDPOINT }.map { |_, params| params[:q] }
    end
  end

  test "finds the article's Commons category through Wikidata and returns its photos, credited to the article" do
    http = FakeHttp.new
    results = Media::CommonsCategoryImages.new(http: http).images("Great Molasses Flood")

    result = results.sole
    assert_equal "commons_category", result.provider
    assert_equal "Great Molasses Flood", result.source_article
    assert_equal "City of Boston Archives", result.credit
    assert_equal [ %(deepcategory:"Boston Molasses Disaster" filetype:bitmap) ], http.searches
  end

  test "falls back to the category's own files when the deep search finds nothing" do
    http = FakeHttp.new(deep: [], shallow: [ "File:Tank 1919.jpg" ])

    results = Media::CommonsCategoryImages.new(http: http).images("Great Molasses Flood")

    assert_equal 1, results.size
    assert_equal %(incategory:"Boston Molasses Disaster" filetype:bitmap), http.searches.last
  end

  test "an article without a Wikidata item or Commons category has no pictures and no video search" do
    assert_empty Media::CommonsCategoryImages.new(http: FakeHttp.new(item: nil)).images("Nowhere")

    categories = Media::CommonsCategoryImages.new(http: FakeHttp.new(category: nil))
    assert_empty categories.images("Nowhere")
    assert_nil categories.video_query("Nowhere")
  end

  test "looks each article's category up once, and searches its videos" do
    http = FakeHttp.new
    categories = Media::CommonsCategoryImages.new(http: http)

    categories.images("Great Molasses Flood")
    assert_equal %(deepcategory:"Boston Molasses Disaster"), categories.video_query("Great Molasses Flood")
    assert_equal 1, http.calls.count { |url, _| url == Media::CommonsCategoryImages::WIKIDATA_ENDPOINT }
  end
end
