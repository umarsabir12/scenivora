require "test_helper"

class Ai::PictureScoutTest < ActiveSupport::TestCase
  # Plays back scripted chat answers in order and records every request.
  class FakeClient
    attr_reader :requests

    def initialize(*answers, error: nil)
      @answers = answers
      @error = error
      @requests = []
    end

    def chat(parameters:)
      @requests << parameters.deep_dup
      raise @error if @error

      message = @answers[[ @requests.size - 1, @answers.size - 1 ].min]
      { "choices" => [ { "message" => message } ], "usage" => { "prompt_tokens" => 4_000, "completion_tokens" => 500, "total_tokens" => 4_500 } }
    end
  end

  class FakeSearch
    attr_reader :queries

    def initialize(results, error: nil)
      @results = results
      @error = error
      @queries = []
    end

    def search(query, limit: 3)
      @queries << query
      raise @error if @error

      @results.first(limit)
    end
  end

  class FakeArticles
    def initialize(pictures = {})
      @pictures = pictures
    end

    def images(article)
      @pictures.fetch(article, [])
    end
  end

  class FakePreviews
    def jpeg(preview)
      "jpeg of #{preview.image_url}"
    end
  end

  def picture(name, taken_on: nil)
    Media::ImageResult.new(provider: "wikimedia_commons", image_url: "https://upload.wikimedia.org/#{name}.jpg",
                           page_url: "https://commons.wikimedia.org/wiki/File:#{name}.jpg", credit: "Archive",
                           license: "Public domain", taken_on: taken_on)
  end

  def tool_call(id, name, arguments)
    { "id" => id, "type" => "function", "function" => { "name" => name, "arguments" => arguments.to_json } }
  end

  def calls(*tool_calls)
    { "role" => "assistant", "content" => nil, "tool_calls" => tool_calls }
  end

  def final(choice, reason = "It shows the wreckage.")
    { "role" => "assistant", "content" => { choice: choice, reason: reason }.to_json }
  end

  setup do
    project = users(:one).projects.create!(prompt: "The Great Molasses Flood", tone: "documentary", target_length_minutes: 3,
                                           settings: { "articles" => [ "Great Molasses Flood" ] })
    @scene = project.scenes.create!(position: 1, text: "The tank burst and molasses filled Commercial Street.", start_ms: 0,
                                    duration_ms: 10_000, plan: { "visual_intent" => "Wreckage on Commercial Street",
                                                                 "search_queries" => [ "tank burst steel plates" ] })
    @wreckage = picture("Wreckage_Commercial_Street_1919", taken_on: "1919-01-15")
    @modern = picture("Langone_Park_2019")
  end

  def scout(client, search: FakeSearch.new([ @wreckage, @modern ]), articles: FakeArticles.new)
    Ai::PictureScout.new(articles: articles, search: search, previews: FakePreviews.new, model: "gpt-5-mini", client: client)
  end

  test "searches, looks, and chooses a picture it looked at, with its cost" do
    client = FakeClient.new(calls(tool_call("t1", "search_commons", query: "Molasses Flood 1919")),
                            calls(tool_call("t2", "look", ids: [ "p1", "p2" ])), final("p1"))
    search = FakeSearch.new([ @wreckage, @modern ])

    result = scout(client, search: search).call(scene: @scene)

    assert_equal @wreckage, result.choice
    assert_equal "It shows the wreckage.", result.reason
    assert_equal [ "Molasses Flood 1919" ], search.queries
    assert_equal 13_500, result.total_tokens
    assert_equal BigDecimal("0.006"), result.cost_usd

    brief = client.requests.first[:messages].second[:content]
    assert_includes brief, "Should show: Wreckage on Commercial Street"
    assert_includes brief, "Articles about this video: Great Molasses Flood"
    assert_includes brief, "Queries that already failed: tank burst steel plates"

    listing = client.requests.second[:messages].find { |message| message[:tool_call_id] == "t1" }[:content]
    assert_includes listing, "p1: Wreckage Commercial Street 1919 | taken 1919-01-15"
    assert_includes listing, "p2: Langone Park 2019"
    previews = client.requests.third[:messages].last
    assert_equal "user", previews[:role]
    assert_equal [ "p1", "p2" ], previews[:content].select { |part| part[:type] == "text" }.map { |part| part[:text] }
    assert_equal "low", previews[:content].second[:image_url][:detail]
    assert_equal "low", client.requests.first[:reasoning_effort]
  end

  test "a picture it found but never looked at, or an id it made up, is not a choice" do
    unseen = FakeClient.new(calls(tool_call("t1", "search_commons", query: "Molasses Flood 1919")), final("p1"))
    made_up = FakeClient.new(calls(tool_call("t1", "look", ids: [ "p9" ])), final("p9"))

    assert_nil scout(unseen).call(scene: @scene).choice
    assert_nil scout(made_up).call(scene: @scene).choice
  end

  test "opens an article's pictures, and leaves out pictures other scenes already show" do
    articles = FakeArticles.new({ "Great Molasses Flood" => [ @wreckage, @modern ] })
    client = FakeClient.new(calls(tool_call("t1", "article_pictures", article: "Great Molasses Flood")), final(nil, "Nothing fits."))

    result = scout(client, articles: articles).call(scene: @scene, used_urls: [ @wreckage.image_url ])

    listing = client.requests.second[:messages].last[:content]
    assert_not_includes listing, "Wreckage"
    assert_includes listing, "p1: Langone Park 2019"
    assert_nil result.choice
    assert_equal "Nothing fits.", result.reason
  end

  test "a failed search is reported to the scout, which goes on" do
    client = FakeClient.new(calls(tool_call("t1", "search_commons", query: "Molasses Flood 1919")), final(nil))

    scout(client, search: FakeSearch.new([], error: Media::Error.new("api.wikimedia.org responded with 503"))).call(scene: @scene)

    assert_match "That search failed", client.requests.second[:messages].last[:content]
  end

  test "stops after MAX_TURNS, and the last turn may not call tools" do
    client = FakeClient.new(calls(tool_call("t1", "search_commons", query: "Molasses 1919")))

    result = scout(client).call(scene: @scene)

    assert_equal Ai::PictureScout::MAX_TURNS, client.requests.size
    assert_equal "none", client.requests.last[:tool_choice]
    assert_nil client.requests.first[:tool_choice]
    assert_nil result.choice
  end

  test "an account with no credit left stops with OutOfCredits" do
    error = Faraday::TooManyRequestsError.new("429", { status: 429, body: '{"error": {"type": "insufficient_quota"}}' })

    assert_raises(Ai::OutOfCredits) { scout(FakeClient.new(error: error)).call(scene: @scene) }
  end
end
