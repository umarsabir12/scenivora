require "test_helper"

class Ai::ResearcherTest < ActiveSupport::TestCase
  class FakeGenerator
    attr_reader :args

    def initialize(text)
      @text = text
    end

    def call(**args)
      @args = args
      Ai::ResearchGenerator::Result.new(text: @text, provider: "openai", model: "gpt-5.5", total_tokens: 25_000,
                                        cost_usd: BigDecimal("0.24"), searches: 5)
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

  setup do
    @project = users(:one).projects.create!(prompt: "Prince Philip: the baby smuggled out of Greece in an orange box",
                                            tone: "dramatic", target_length_minutes: 5, category: "biography",
                                            instructions: "Focus on the escape.")
  end

  def answer
    "```json\n" + {
      facts: [ "Philip was born at Mon Repos, Corfu, on 10 June 1921.", "", "HMS Calypso evacuated the family in December 1922." ],
      articles: [ "Prince Philip", "HMS Calypso (D61)", "Invented Escape Article" ],
      visual_subjects: [
        { name: "HMS Calypso", kind: "ship", article: "HMS Calypso (D61)", year: "1922" },
        { name: "Orange crate cot", kind: "furniture", article: "Made Up Crate", year: nil },
        { name: "hms calypso", kind: "ship" },
        "not a hash"
      ],
      uncertain: [ "That he was hidden as cargo is a later embellishment." ]
    }.to_json + "\n```"
  end

  def research(titles: FakeTitles.new({ "Prince Philip" => "Prince Philip, Duke of Edinburgh", "HMS Calypso (D61)" => "HMS Calypso (D61)" }))
    generator = FakeGenerator.new(answer)
    [ Ai::Researcher.new(generator: generator, titles: titles).call(@project), generator ]
  end

  test "searches Wikipedia only, with the brief, category and instructions" do
    _research, generator = research

    assert_equal [ "en.wikipedia.org" ], generator.args[:domains]
    assert_equal Ai::Researcher::MAX_SEARCHES, generator.args[:max_searches]
    assert_includes generator.args[:input], "Brief: Prince Philip: the baby smuggled"
    assert_includes generator.args[:input], "Category: biography (One person's life"
    assert_includes generator.args[:input], "The creator's instructions: Focus on the escape."
  end

  test "keeps facts and subjects, and only real article titles" do
    result, = research

    assert_equal [ "Philip was born at Mon Repos, Corfu, on 10 June 1921.", "HMS Calypso evacuated the family in December 1922." ],
                 result.facts
    assert_equal [ "Prince Philip, Duke of Edinburgh", "HMS Calypso (D61)" ], result.articles
    assert_equal [ "Invented Escape Article", "Made Up Crate" ], result.dropped_articles
    assert_equal [ { "name" => "HMS Calypso", "kind" => "ship", "article" => "HMS Calypso (D61)", "year" => "1922" },
                   { "name" => "Orange crate cot", "kind" => "object", "article" => nil, "year" => nil } ], result.visual_subjects
    assert_equal [ "That he was hidden as cargo is a later embellishment." ], result.uncertain
    assert_equal BigDecimal("0.24"), result.cost_usd
    assert_equal 5, result.searches
  end

  test "keeps the titles as given when Wikipedia can't be reached" do
    result, = research(titles: FakeTitles.new({}, error: Media::Error.new("en.wikipedia.org responded with 503")))

    assert_equal [ "Prince Philip", "HMS Calypso (D61)", "Invented Escape Article" ], result.articles
    assert_empty result.dropped_articles
  end

  test "an answer without facts is an error" do
    researcher = Ai::Researcher.new(generator: FakeGenerator.new("{\"articles\": []}"), titles: FakeTitles.new({}))

    assert_raises(Ai::Error) { researcher.call(@project) }
  end

  test "the key changes with the brief, category or instructions, not with tone or length" do
    key = Ai::Researcher.key_for(@project)

    @project.tone = "casual"
    @project.target_length_minutes = 8
    assert_equal key, Ai::Researcher.key_for(@project)

    @project.instructions = "Focus on his naval career."
    assert_not_equal key, Ai::Researcher.key_for(@project)
  end
end
