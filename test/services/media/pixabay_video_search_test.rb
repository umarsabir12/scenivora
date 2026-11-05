require "test_helper"

class Media::PixabayVideoSearchTest < ActiveSupport::TestCase
  class FakeHttp
    attr_reader :calls

    def initialize(hits)
      @hits = hits
      @calls = []
    end

    def get(url, params = {})
      @calls << [ url, params ]
      { "hits" => @hits }
    end
  end

  def hit(id, tags:, duration: 15, ai: false, heights: { "large" => 2160, "medium" => 1080, "small" => 720 })
    { "id" => id, "pageURL" => "https://pixabay.com/videos/id-#{id}/", "tags" => tags, "duration" => duration, "user" => "maker",
      "isAiGenerated" => ai,
      "videos" => heights.to_h { |size, height| [ size, { "url" => "https://cdn.pixabay.com/#{id}_#{size}.mp4", "height" => height,
                                                         "thumbnail" => "https://cdn.pixabay.com/#{id}_#{size}.jpg" } ] } }
  end

  def search(hits, query)
    http = FakeHttp.new(hits)
    [ Media::PixabayVideoSearch.new(api_key: "test-key", http: http).search(query, limit: 3), http ]
  end

  test "keeps only clips whose tags hold every telling word of the query" do
    results, http = search([ hit(1, tags: "hong kong, cruise, harbour"), hit(2, tags: "boston, harbor, harbour, boats") ], "Boston harbour")

    assert_equal [ "https://pixabay.com/videos/id-2/" ], results.map(&:page_url)
    _url, params = http.calls.sole
    assert_equal "test-key", params[:key]
    assert_equal "Boston harbour", params[:q]
  end

  test "ignores filler words like aerial and drone" do
    results, = search([ hit(1, tags: "corfu, greece, sea") ], "Corfu aerial drone footage")

    assert_equal 1, results.size
  end

  test "leaves out AI-generated and very short clips" do
    results, = search([ hit(1, tags: "corfu", ai: true), hit(2, tags: "corfu", duration: 2), hit(3, tags: "corfu") ], "Corfu")

    assert_equal [ "https://pixabay.com/videos/id-3/" ], results.map(&:page_url)
  end

  test "picks the largest file up to 1080p, with its poster, credit and licence" do
    result = search([ hit(1, tags: "corfu") ], "Corfu").first.sole

    assert_equal "https://cdn.pixabay.com/1_medium.mp4", result.video_url
    assert_equal "https://cdn.pixabay.com/1_medium.jpg", result.poster_url
    assert_equal "maker on Pixabay", result.credit
    assert_equal "Pixabay Content License", result.license
    assert_equal 15_000, result.duration_ms
    assert_equal "pixabay", result.provider
  end
end
