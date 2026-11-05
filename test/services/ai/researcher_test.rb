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
                                            tone: "dramatic", target_length_minutes: 5,
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
      uncertain: [ "That he was hidden as cargo is a later embellishment." ],
      story_check: { status: "attributed", note: "  Biographers report the fruit-box cot. " }
    }.to_json + "\n```"
  end

  def research(titles: FakeTitles.new({ "Prince Philip" => "Prince Philip, Duke of Edinburgh", "HMS Calypso (D61)" => "HMS Calypso (D61)" }))
    generator = FakeGenerator.new(answer)
    [ Ai::Researcher.new(generator: generator, titles: titles).call(@project), generator ]
  end

  test "searches Wikipedia first, then news and reference sites, with the brief and instructions" do
    _research, generator = research

    assert_equal "en.wikipedia.org", generator.args[:domains].first
    assert_includes generator.args[:domains], "bbc.co.uk"
    assert_equal Ai::Researcher::MAX_SEARCHES, generator.args[:max_searches]
    assert_equal "low", generator.args[:effort]
    assert_includes generator.args[:input], "Brief: Prince Philip: the baby smuggled"
    assert_includes generator.args[:input], "The creator's instructions: Focus on the escape."
  end

  test "researches with the small model unless OPENAI_RESEARCH_MODEL says otherwise" do
    previous = ENV["OPENAI_RESEARCH_MODEL"]
    ENV.delete("OPENAI_RESEARCH_MODEL")
    assert_equal "gpt-5-mini", Ai::Researcher.model
    ENV["OPENAI_RESEARCH_MODEL"] = "gpt-5.5"
    assert_equal "gpt-5.5", Ai::Researcher.model
  ensure
    ENV["OPENAI_RESEARCH_MODEL"] = previous
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
    assert_equal({ "status" => "attributed", "note" => "Biographers report the fruit-box cot." }, result.story_check)
  end

  test "a missing or unknown story check counts as verified" do
    generator = FakeGenerator.new({ facts: [ "A fact." ], story_check: { status: "probably" } }.to_json)
    result = Ai::Researcher.new(generator: generator, titles: FakeTitles.new({})).call(@project)

    assert_equal({ "status" => "verified", "note" => "" }, result.story_check)
    assert_equal "verified", result.to_settings("key")["story_check"]["status"]
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

  test "the key changes with the brief or instructions, not with tone or length" do
    key = Ai::Researcher.key_for(@project)

    @project.tone = "casual"
    @project.target_length_minutes = 8
    assert_equal key, Ai::Researcher.key_for(@project)

    @project.instructions = "Focus on his naval career."
    assert_not_equal key, Ai::Researcher.key_for(@project)
  end
end
