require "test_helper"

class Media::CommonsCategoryImagesTest < ActiveSupport::TestCase
  # Answers each endpoint the way Wikipedia, Wikidata and the Commons search do.
  class FakeHttp
    attr_reader :calls

    def initialize(item: "Q1", category: "Boston Molasses Disaster", deep: [ "File:Wreckage 1919.jpg", "File:Logo.jpg" ], shallow: [],
                   depicts: [])
      @item = item
      @category = category
      @deep = deep
      @shallow = shallow
      @depicts = depicts
      @calls = []
    end

    def get(url, params = {})
      @calls << [ url, params ]
      if url == Media::CommonsCategoryImages::WIKIDATA_ENDPOINT
        claims = @category ? { "P373" => [ { "mainsnak" => { "datavalue" => { "value" => @category } } } ] } : {}
        { "entities" => { @item => { "claims" => claims } } }
      elsif url == Media::CommonsSearch::SEARCH_ENDPOINT
        titles = if params[:q].start_with?("haswbstatement:") then @depicts
        elsif params[:q].start_with?("deepcategory:") then @deep
        else @shallow
        end
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
    assert_equal [ "haswbstatement:P180=Q1 filetype:bitmap", %(deepcategory:"Boston Molasses Disaster" filetype:bitmap) ], http.searches
  end

  test "photos tagged as depicting the subject come first, as their own source, even outside the category" do
    http = FakeHttp.new(item: "Q40026", category: nil, depicts: [ "File:Venice 2009 (26).jpg", "File:Wreckage 1919.jpg" ])

    results = Media::CommonsCategoryImages.new(http: http).images("Sylvester Stallone")

    assert_equal [ "haswbstatement:P180=Q40026 filetype:bitmap" ], http.searches
    assert_equal %w[commons_depicts commons_depicts], results.map(&:provider)
    assert_equal [ "Sylvester Stallone" ], results.map(&:source_article).uniq
  end

  test "a photo both depicting the subject and in its category counts once, as depicting it" do
    http = FakeHttp.new(depicts: [ "File:Wreckage 1919.jpg" ])

    results = Media::CommonsCategoryImages.new(http: http).images("Great Molasses Flood")

    assert_equal [ "commons_depicts" ], results.map(&:provider)
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
