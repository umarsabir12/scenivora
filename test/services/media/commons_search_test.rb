require "test_helper"

class Media::CommonsSearchTest < ActiveSupport::TestCase
  # Answers the search endpoint and the metadata endpoint with canned responses, and records calls.
  class FakeHttp
    attr_reader :calls

    def initialize(search:, metadata:)
      @search = search
      @metadata = metadata
      @calls = []
    end

    def get(url, params = {})
      @calls << [ url, params ]
      url == Media::CommonsSearch::SEARCH_ENDPOINT ? @search : @metadata
    end
  end

  SEARCH = {
    "pages" => [
      { "id" => 1, "key" => "Tesla_1890.jpg", "title" => "File:Tesla 1890.jpg" },
      { "id" => 2, "key" => "Diagram.svg", "title" => "File:Diagram.svg" },
      { "id" => 3, "key" => "Bad.jpg", "title" => "File:Bad.jpg" },
      { "id" => 4, "key" => "Old_Tesla.jpg", "title" => "File:Old Tesla.jpg" }
    ]
  }.freeze

  def page(title, mime:, license:, artist: "<a href='x'>Photographer Jane</a>")
    {
      "title" => title,
      "imageinfo" => [ {
        "mime" => mime,
        "thumburl" => "https://upload.wikimedia.org/thumb/#{title.parameterize}.jpg",
        "descriptionurl" => "https://commons.wikimedia.org/wiki/#{title.tr(' ', '_')}",
        "extmetadata" => {
          "Artist" => { "value" => artist },
          "LicenseShortName" => { "value" => license }
        }
      } ]
    }
  end

  METADATA = {
    "query" => {
      "pages" => [
        { "title" => "File:Tesla 1890.jpg", "imageinfo" => [ {
            "mime" => "image/jpeg", "thumburl" => "https://upload.wikimedia.org/thumb/tesla.jpg",
            "descriptionurl" => "https://commons.wikimedia.org/wiki/File:Tesla_1890.jpg",
            "extmetadata" => { "Artist" => { "value" => "<a href='x'>Photographer Jane</a>" },
                               "LicenseShortName" => { "value" => "CC BY-SA 4.0" } }
          } ] },
        { "title" => "File:Diagram.svg", "imageinfo" => [ { "mime" => "image/svg+xml", "url" => "https://x/d.svg",
            "extmetadata" => { "LicenseShortName" => { "value" => "CC0" } } } ] },
        { "title" => "File:Bad.jpg", "imageinfo" => [ { "mime" => "image/jpeg", "thumburl" => "https://x/bad.jpg",
            "extmetadata" => { "LicenseShortName" => { "value" => "CC BY-NC 4.0" } } } ] },
        { "title" => "File:Old Tesla.jpg", "imageinfo" => [ { "mime" => "image/jpeg", "thumburl" => "https://x/old.jpg",
            "extmetadata" => { "LicenseShortName" => { "value" => "Public domain" } } } ] }
      ]
    }
  }.freeze

  test "keeps only photos with a reusable license, with credit and source" do
    http = FakeHttp.new(search: SEARCH, metadata: METADATA)

    results = Media::CommonsSearch.new(http: http).search("Nikola Tesla", limit: 5)

    assert_equal [ "https://upload.wikimedia.org/thumb/tesla.jpg", "https://x/old.jpg" ], results.map(&:image_url)
    tesla = results.first
    assert_equal "wikimedia_commons", tesla.provider
    assert_equal "Photographer Jane", tesla.credit
    assert_equal "CC BY-SA 4.0", tesla.license
    assert_equal "https://commons.wikimedia.org/wiki/File:Tesla_1890.jpg", tesla.page_url
  end

  test "searches with the bitmap filter, then asks for metadata for the file titles" do
    http = FakeHttp.new(search: SEARCH, metadata: METADATA)

    Media::CommonsSearch.new(http: http).search("Nikola Tesla", limit: 2)

    (search_url, search_params), (meta_url, meta_params) = http.calls
    assert_equal Media::CommonsSearch::SEARCH_ENDPOINT, search_url
    assert_equal "Nikola Tesla filetype:bitmap", search_params[:q]
    assert_equal Media::CommonsSearch::METADATA_ENDPOINT, meta_url
    assert_equal "File:Tesla 1890.jpg|File:Diagram.svg|File:Bad.jpg|File:Old Tesla.jpg", meta_params[:titles]
  end

  test "returns nothing without a metadata call when the search finds no files" do
    http = FakeHttp.new(search: { "pages" => [] }, metadata: METADATA)

    assert_equal [], Media::CommonsSearch.new(http: http).search("zzz", limit: 3)
    assert_equal 1, http.calls.size
  end

  test "stops at the requested limit" do
    http = FakeHttp.new(search: SEARCH, metadata: METADATA)

    assert_equal 1, Media::CommonsSearch.new(http: http).search("Nikola Tesla", limit: 1).size
  end
end
