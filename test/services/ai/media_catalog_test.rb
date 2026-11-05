require "test_helper"

class Ai::MediaCatalogTest < ActiveSupport::TestCase
  # Answers each batch from a block given the ids it was shown, and records every request.
  class FakeClient
    attr_reader :requests

    def initialize(error: nil, &answer)
      @answer = answer
      @error = error
      @requests = []
    end

    def chat(parameters:)
      @requests << parameters.deep_dup
      raise @error if @error

      ids = parameters[:messages].last[:content].filter_map { |part| part[:text]&.split(" | ")&.first if part[:type] == "text" }.grep(/\Am\d+\z/)
      { "choices" => [ { "message" => { "content" => { pictures: @answer.call(ids) }.to_json } } ],
        "usage" => { "prompt_tokens" => 4_000, "completion_tokens" => 1_000, "total_tokens" => 5_000 } }
    end
  end

  class FakePreviews
    attr_reader :urls

    def initialize(missing: [])
      @missing = missing
      @urls = []
    end

    def jpeg(preview)
      @urls << preview.image_url
      "jpeg" unless @missing.any? { |name| preview.image_url.include?(name) }
    end
  end

  def picture(name, taken_on: nil)
    Media::ImageResult.new(provider: "commons_category", image_url: "https://upload.wikimedia.org/wikipedia/commons/a/ab/#{name}.jpg",
                           page_url: "https://commons.wikimedia.org/wiki/File:#{name}.jpg", credit: "Archive",
                           license: "CC BY-SA 4.0", taken_on: taken_on)
  end

  def described(id)
    { id: id, shows: "Ronaldo lifting the trophy", people: [ "Cristiano Ronaldo", "" ], year: "taken 2016-07-10",
      kind: "celebration", usable: true }
  end

  test "describes every picture in batches, with labels, small thumbnails and the cost" do
    items = (1..17).map { |n| picture("Euro_2016_final_#{n}", taken_on: "2016-07-10") }
    previews = FakePreviews.new
    client = FakeClient.new { |ids| ids.map { |id| described(id) } }

    result = Ai::MediaCatalog.new(previews: previews, model: "gpt-5-mini", client: client).call(topic: "Ronaldo retires", items: items)

    assert_equal 2, client.requests.size
    assert_equal %w[m1 m17], [ result.entries.first.id, result.entries.last.id ]
    entry = result.entries.first
    assert_equal items.first, entry.item
    assert_equal [ "Cristiano Ronaldo" ], entry.people
    assert_equal "2016", entry.year
    assert_equal "celebration", entry.kind
    assert entry.usable
    assert_empty result.failed
    assert_equal 10_000, result.total_tokens
    assert_equal BigDecimal("0.006"), result.cost_usd

    content = client.requests.first[:messages].last[:content]
    assert_equal "Topic: Ronaldo retires", content.first[:text]
    assert_equal "m1 | Euro 2016 final 1 | taken 2016-07-10", content.second[:text]
    assert_equal "low", content.third[:image_url][:detail]
    assert_includes previews.urls.first, "/thumb/a/ab/Euro_2016_final_1.jpg/330px-Euro_2016_final_1.jpg"
  end

  test "a picture without a preview or a description is listed as failed, and unknown kinds become other" do
    items = [ picture("Logo"), picture("Missing"), picture("Crowd") ]
    client = FakeClient.new { [ { id: "m1", shows: "The federation crest", kind: "badge", usable: false } ] }

    result = Ai::MediaCatalog.new(previews: FakePreviews.new(missing: [ "Missing" ]), client: client).call(topic: "Ronaldo", items: items)

    assert_equal [ "m1" ], result.entries.map(&:id)
    assert_equal "other", result.entries.first.kind
    assert_not result.entries.first.usable
    assert_equal %w[m2 m3], result.failed.sort
  end

  test "makes thumbnail URLs for Wikimedia files and leaves other sources alone" do
    assert_equal "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c3/Ronaldo_2023.jpg/330px-Ronaldo_2023.jpg",
                 Ai::MediaCatalog.thumb_url("https://upload.wikimedia.org/wikipedia/commons/c/c3/Ronaldo_2023.jpg?utm_source=x")
    assert_equal "https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c6/Derby.JPG/330px-Derby.JPG",
                 Ai::MediaCatalog.thumb_url("https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c6/Derby.JPG/1920px-Derby.JPG?utm=1")
    assert_equal "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Crest.svg/330px-Crest.svg.png",
                 Ai::MediaCatalog.thumb_url("https://upload.wikimedia.org/wikipedia/commons/1/1a/Crest.svg")
    assert_equal "https://cdn.pixabay.com/photo/lisbon.jpg", Ai::MediaCatalog.thumb_url("https://cdn.pixabay.com/photo/lisbon.jpg")
  end

  test "an account with no credit left stops with OutOfCredits" do
    error = Faraday::TooManyRequestsError.new("429", { status: 429, body: '{"error": {"type": "insufficient_quota"}}' })

    assert_raises(Ai::OutOfCredits) do
      Ai::MediaCatalog.new(previews: FakePreviews.new, client: FakeClient.new(error: error)).call(topic: "Ronaldo", items: [ picture("A") ])
    end
  end
end
