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

  test "an answer without a plan is an error" do
    director = Ai::Director.new(generator: FakeGenerator.new("Sorry, I can't."), titles: FakeTitles.new({}))

    assert_raises(Ai::Error) { director.plan(topic: "x", scenes: scenes) }
  end
end
