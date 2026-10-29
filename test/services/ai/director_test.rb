require "test_helper"

class Ai::DirectorTest < ActiveSupport::TestCase
  class FakeGenerator
    attr_reader :args

    def initialize(text)
      @text = text
    end

    def call(**args)
      @args = args
      Ai::ResearchGenerator::Result.new(text: @text, provider: "openai", model: "gpt-5.5", total_tokens: 30_000,
                                        cost_usd: BigDecimal("0.3"), searches: 4)
    end
  end

  class FakeTitles
    def initialize(real, error: nil)
      @real = real
      @error = error
    end

    def resolve(titles)
      raise @error if @error

      titles.uniq.to_h { |title| [ title, @real.fetch(title, nil) ] }
    end
  end

  Beat = Struct.new(:position, :text, :duration_ms)

  def scenes
    [ Beat.new(1, "The baby left Greece on a ship.", 10_000), Beat.new(2, "He married in 1947.", 10_000) ]
  end

  def answer
    "Here is the plan:\n```json\n" + {
      facts: [ "Philip left Corfu on HMS Calypso in December 1922." ],
      topic_depiction: "normal",
      articles: [ "Prince Philip", "Invented Article" ],
      beats: [
        { beat: 1, subject: "HMS Calypso", articles: [ "HMS Calypso (D61)" ], visual_intent: "The cruiser HMS Calypso",
          search_queries: [ "HMS Calypso 1922" ] },
        { beat: 2, articles: [ "Wedding of Princess Elizabeth and Prince Philip" ], search_queries: [ "royal wedding 1947" ] }
      ]
    }.to_json + "\n```"
  end

  def real_titles
    { "Prince Philip" => "Prince Philip, Duke of Edinburgh", "HMS Calypso (D61)" => "HMS Calypso (D61)",
      "Wedding of Princess Elizabeth and Prince Philip" => "Wedding of Princess Elizabeth and Philip Mountbatten" }
  end

  test "researches on Wikipedia, then plans with real article titles only" do
    generator = FakeGenerator.new(answer)
    plan = Ai::Director.new(generator: generator, titles: FakeTitles.new(real_titles)).plan(topic: "Prince Philip", scenes: scenes)

    assert_equal [ "Prince Philip, Duke of Edinburgh" ], plan.result.articles
    assert_equal [ "HMS Calypso (D61)" ], plan.result.plans[1].articles
    assert_equal [ "Wedding of Princess Elizabeth and Philip Mountbatten" ], plan.result.plans[2].articles
    assert_equal [ "Invented Article" ], plan.dropped_articles
    assert_equal [ "Philip left Corfu on HMS Calypso in December 1922." ], plan.facts
    assert_equal 4, plan.searches
    assert_equal BigDecimal("0.3"), plan.result.cost_usd
    assert_equal [ "en.wikipedia.org" ], generator.args[:domains]
    assert_includes generator.args[:instructions], "research the real history"
    assert_includes generator.args[:input], "Beat 1 (10.0 s): The baby left Greece on a ship."
  end

  test "keeps the titles as given when Wikipedia can't be reached" do
    titles = FakeTitles.new({}, error: Media::Error.new("en.wikipedia.org responded with 503"))
    plan = Ai::Director.new(generator: FakeGenerator.new(answer), titles: titles).plan(topic: "Prince Philip", scenes: scenes)

    assert_equal [ "Prince Philip", "Invented Article" ], plan.result.articles
    assert_empty plan.dropped_articles
  end

  test "estimates about a quarter dollar for a 12-scene video with gpt-5.5" do
    estimate = Ai::Director.estimated_cost(12)

    assert estimate > 0.2
    assert estimate < 0.4
  end

  class FakePreviews
    def jpeg(media)
      "jpeg-#{media.id}"
    end
  end

  def storyboard
    project = users(:one).projects.create!(prompt: "Prince Philip", tone: "documentary", target_length_minutes: 3)
    [ [ "The baby left on a ship.", "HMS Calypso.jpg", "Reagans with Prince Philip.jpg" ],
      [ "He married in 1947.", "Wedding portrait 1947.jpg", nil ] ].each_with_index.map do |(text, pick, other), index|
      scene = project.scenes.create!(position: index + 1, text: text, start_ms: index * 10_000, duration_ms: 10_000,
                                     plan: { "visual_intent" => text })
      scene.images.create!(provider: "wikipedia_article", image_url: "https://upload.wikimedia.org/#{pick}", selected: true,
                           page_url: "https://commons.wikimedia.org/wiki/File:#{pick}", credit: "x", license: "CC0",
                           source_article: "HMS Calypso (D61)")
      if other
        scene.images.create!(provider: "wikimedia_commons", image_url: "https://upload.wikimedia.org/#{other}",
                             page_url: "https://commons.wikimedia.org/wiki/File:#{other}", credit: "x", license: "CC0", taken_on: "1985")
      end
      scene.reload
    end
  end

  test "reviews the whole storyboard: current pictures as images, other candidates by title" do
    scenes = storyboard
    other = scenes.first.images.reject(&:selected?).first
    answer = { scenes: [ { scene: 1, action: "swap", candidate: other.id, note: "Better." },
                         { scene: 2, action: "reject", note: "Modern photo.", ai_prompt: "A 1947 wedding at Westminster Abbey" } ] }
    generator = FakeGenerator.new(answer.to_json)

    review = Ai::Director.new(generator: generator, previews: FakePreviews.new)
                         .review(topic: "Prince Philip", scenes: scenes, facts: [ "Left Corfu in 1922." ], fixed: [ 2 ])

    assert_equal 2, generator.args[:images].size
    assert_nil generator.args[:domains]
    assert_equal "low", generator.args[:effort]
    prompt = generator.args[:input]
    assert_includes prompt, "- Left Corfu in 1922."
    assert_includes prompt, "Scene 2 (10 s, rule: normal) fixed"
    assert_includes prompt, "Current picture: [picture 1] \"HMS Calypso\" (from Wikipedia article \"HMS Calypso (D61)\")"
    assert_includes prompt, "##{other.id} \"Reagans with Prince Philip\" (taken 1985)"
    assert_equal Ai::Director::Decision.new(action: "swap", candidate_id: other.id, note: "Better.", ai_prompt: nil), review.decisions[1]
    assert_equal "A 1947 wedding at Westminster Abbey", review.decisions[2].ai_prompt
    assert_equal BigDecimal("0.3"), review.cost_usd
  end

  test "a swap to a candidate that isn't the scene's own is ignored, and so are unknown actions" do
    scenes = storyboard
    answer = { scenes: [ { scene: 1, action: "swap", candidate: 999_999 }, { scene: 2, action: "delete" },
                         { scene: 7, action: "keep" } ] }

    review = Ai::Director.new(generator: FakeGenerator.new(answer.to_json), previews: FakePreviews.new)
                         .review(topic: "Prince Philip", scenes: scenes, facts: [])

    assert_empty review.decisions
  end

  test "an answer without a plan is an error" do
    director = Ai::Director.new(generator: FakeGenerator.new("Sorry, I can't."), titles: FakeTitles.new({}))

    assert_raises(Ai::Error) { director.plan(topic: "x", scenes: scenes) }
  end
end
