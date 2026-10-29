require "test_helper"

class Media::WikipediaTitlesTest < ActiveSupport::TestCase
  class FakeHttp
    attr_reader :params

    def initialize(response)
      @response = response
    end

    def get(_url, params)
      @params = params
      @response
    end
  end

  test "follows normalising and redirects to the real title, and marks missing articles" do
    http = FakeHttp.new({ "query" => {
      "normalized" => [ { "from" => "prince Philip", "to" => "Prince Philip" } ],
      "redirects" => [ { "from" => "Prince Philip", "to" => "Prince Philip, Duke of Edinburgh" } ],
      "pages" => [ { "title" => "Prince Philip, Duke of Edinburgh" }, { "title" => "HMS Calypso (D61)" },
                   { "title" => "Made Up Article", "missing" => true } ]
    } })

    resolved = Media::WikipediaTitles.new(http: http).resolve([ "prince Philip", "HMS Calypso (D61)", "Made Up Article", "", nil ])

    assert_equal({ "prince Philip" => "Prince Philip, Duke of Edinburgh", "HMS Calypso (D61)" => "HMS Calypso (D61)",
                   "Made Up Article" => nil }, resolved)
    assert_equal "prince Philip|HMS Calypso (D61)|Made Up Article", http.params[:titles]
    assert_equal 1, http.params[:redirects]
  end

  test "no titles means no request" do
    http = FakeHttp.new({})
    assert_equal({}, Media::WikipediaTitles.new(http: http).resolve([]))
    assert_nil http.params
  end
end
