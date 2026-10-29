require "test_helper"

class Media::WikipediaArticleImagesTest < ActiveSupport::TestCase
  class FakeHttp
    attr_reader :calls

    def initialize(response)
      @response = response
      @calls = []
    end

    def get(url, params = {})
      @calls << [ url, params ]
      @response
    end
  end

  def page(title, mime: "image/jpeg", license: "Public domain", width: 1200, height: 900)
    { "title" => title, "imageinfo" => [ {
      "mime" => mime, "width" => width, "height" => height,
      "thumburl" => "https://upload.wikimedia.org/thumb/#{title.parameterize}.jpg",
      "descriptionurl" => "https://en.wikipedia.org/wiki/#{title.tr(' ', '_')}",
      "extmetadata" => { "Artist" => { "value" => "Royal Navy" }, "LicenseShortName" => { "value" => license },
                         "ImageDescription" => { "value" => "HMS Calypso at sea" }, "DateTimeOriginal" => { "value" => "1922" } }
    } ] }
  end

  def images_from(*pages)
    http = FakeHttp.new({ "query" => { "pages" => pages } })
    [ Media::WikipediaArticleImages.new(http: http).images("HMS Calypso (D61)"), http ]
  end

  test "returns the article's pictures with credit, license, metadata, provider and the article" do
    results, http = images_from(page("File:HMS Calypso (D61).jpg"))

    result = results.sole
    assert_equal "wikipedia_article", result.provider
    assert_equal "HMS Calypso (D61)", result.source_article
    assert_equal "Royal Navy", result.credit
    assert_equal "Public domain", result.license
    assert_equal "HMS Calypso at sea", result.description
    assert_equal "1922", result.taken_on

    _url, params = http.calls.sole
    assert_equal "images", params[:generator]
    assert_equal "HMS Calypso (D61)", params[:titles]
    assert_equal 1, params[:redirects]
  end

  test "drops SVGs and other non-photos, small images and icons, logos, flags, seals and signatures" do
    results, = images_from(
      page("File:Royal Navy diagram.svg", mime: "image/svg+xml"),
      page("File:Badge.png", width: 120, height: 120),
      page("File:Royal Navy logo.jpg"), page("File:Flag of Greece.jpg"), page("File:Coat of arms of Corfu.jpg"),
      page("File:Philip signature.png"), page("File:Great Seal.jpg"), page("File:Ship map icon.png"),
      page("File:Calypso in Malta 1923.jpg")
    )

    assert_equal [ "https://upload.wikimedia.org/thumb/file-calypso-in-malta-1923-jpg.jpg" ], results.map(&:image_url)
  end

  test "fair-use and other non-free files never get through" do
    results, = images_from(page("File:Death notice.jpg", license: "Fair use"),
                           page("File:Portrait.jpg", license: "Non-free media"))

    assert_equal [], results
  end

  test "an article that doesn't exist returns nothing" do
    http = FakeHttp.new({ "batchcomplete" => true })

    assert_equal [], Media::WikipediaArticleImages.new(http: http).images("No Such Article (Ship)")
  end
end
