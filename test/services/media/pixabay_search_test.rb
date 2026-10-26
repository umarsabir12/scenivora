require "test_helper"

class Media::PixabaySearchTest < ActiveSupport::TestCase
  class FakeHttp
    attr_reader :calls

    def initialize(body)
      @body = body
      @calls = []
    end

    def get(url, params = {})
      @calls << [ url, params ]
      @body
    end
  end

  test "maps hits to images with the photographer credit" do
    http = FakeHttp.new("hits" => [ {
      "webformatURL" => "https://pixabay.example/a.jpg", "pageURL" => "https://pixabay.example/p/1", "user" => "jane"
    } ])

    results = Media::PixabaySearch.new(api_key: "test-key", http: http).search("tesla", limit: 3)

    assert_equal 1, results.size
    assert_equal "jane on Pixabay", results.first.credit
    assert_equal "Pixabay Content License", results.first.license
    assert_equal "test-key", http.calls.first.last[:key]
  end
end
