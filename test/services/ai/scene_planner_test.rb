require "test_helper"

class Ai::ScenePlannerTest < ActiveSupport::TestCase
  # Returns a canned text result and records what was sent.
  class FakeGenerator
    attr_reader :calls

    def initialize(text, error: nil)
      @text = text
      @error = error
      @calls = []
    end

    def call(**args)
      @calls << args
      raise @error if @error

      Ai::TextGenerator::Result.new(text: @text, provider: "openai", model: "gpt-4o-mini",
                                    total_tokens: 900, cost_usd: BigDecimal("0.0002"))
    end
  end

  Beat = Struct.new(:position, :text, :duration_ms)

  def beats
    [ Beat.new(1, "Nikola Tesla was born in Croatia.", 10_000), Beat.new(2, "He moved to New York.", 10_000) ]
  end

  def planner_for(text, error: nil)
    generator = FakeGenerator.new(text, error: error)
    [ Ai::ScenePlanner.new(generator: generator), generator ]
  end

  test "with research, plans from its facts and pictures, and names only its checked articles" do
    answer = { articles: [ "HMS Calypso (D61)", "Invented Article" ],
               beats: [ { beat: 1, search_queries: [ "HMS Calypso 1922" ], articles: [ "HMS Calypso (D61)", "Made Up Ship" ] } ] }.to_json
    planner, generator = planner_for(answer)
    research = { "facts" => [ "HMS Calypso evacuated the family in December 1922." ], "articles" => [ "Prince Philip, Duke of Edinburgh" ],
                 "visual_subjects" => [ { "name" => "HMS Calypso", "kind" => "ship", "article" => "HMS Calypso (D61)", "year" => "1922" } ] }

    result = planner.call(topic: "Prince Philip", scenes: beats, research: research,
                          pictures: [ "HMS Calypso; taken 1919; article: HMS Calypso (D61)" ])

    call = generator.calls.first
    assert_includes call[:system_prompt], "The topic has been researched already"
    assert_includes call[:user_prompt], "- HMS Calypso evacuated the family in December 1922."
    assert_includes call[:user_prompt], "- HMS Calypso (article: HMS Calypso (D61)) 1922"
    assert_includes call[:user_prompt], "Articles: Prince Philip, Duke of Edinburgh; HMS Calypso (D61)"
    assert_includes call[:user_prompt], "- HMS Calypso; taken 1919; article: HMS Calypso (D61)"
    assert_equal [ "HMS Calypso (D61)" ], result.articles
    assert_equal [ "HMS Calypso (D61)" ], result.plans[1].articles
  end

  test "without research, plans from the narration alone" do
    planner, generator = planner_for('{"beats": []}')

    planner.call(topic: "Nikola Tesla", scenes: beats)

    assert_not_includes generator.calls.first[:system_prompt], "researched already"
    assert_not_includes generator.calls.first[:user_prompt], "Research facts"
  end

  test "asks for JSON and sends the topic and each beat with its duration" do
    planner, generator = planner_for('{"beats": []}')

    planner.call(topic: "Nikola Tesla", scenes: beats)

    call = generator.calls.first
    assert_equal true, call[:json]
    assert_match "Topic: Nikola Tesla", call[:user_prompt]
    assert_match "Beat 2 (10.0 s): He moved to New York.", call[:user_prompt]
  end

  test "maps each beat's queries and flags onto the matching scene" do
    text = {
      beats: [
        { beat: 1, visual_intent: "A portrait", subject_type: "real_person",
          search_queries: [ "Nikola Tesla 1890", "Tesla portrait" ], ai_fallback_allowed: false },
        { beat: 2, visual_intent: "Manhattan street", subject_type: "real_place",
          search_queries: [ "New York City 1900" ], ai_fallback_allowed: true }
      ]
    }.to_json

    planner, = planner_for(text)
    result = planner.call(topic: "Nikola Tesla", scenes: beats)

    first = result.plans[1]
    assert_equal [ "Nikola Tesla 1890", "Tesla portrait" ], first.search_queries
    assert_equal "real_person", first.subject_type
    assert_equal false, first.ai_fallback_allowed
    assert_equal "New York City 1900", result.plans[2].search_queries.first
    assert_equal true, result.plans[2].ai_fallback_allowed
  end

  test "a scene still skipped after the retry gets an empty plan that is not a mood scene" do
    text = { beats: [ { beat: 1, search_queries: [ "Tesla" ] } ] }.to_json

    planner, generator = planner_for(text)
    result = planner.call(topic: "Tesla", scenes: beats)

    plan = result.plans[2]
    assert_equal [], plan.search_queries
    assert_equal "object", plan.subject_type
    assert_not_includes FindSceneImagesJob::MOOD_SUBJECTS, plan.subject_type
    assert plan.ai_fallback_allowed
    assert_equal 2, generator.calls.size
  end

  # Answers each call in turn and records what was sent.
  class SequenceGenerator
    attr_reader :calls

    def initialize(*texts)
      @texts = texts
      @calls = []
    end

    def call(**args)
      @calls << args
      Ai::TextGenerator::Result.new(text: @texts.shift.to_json, provider: "openai", model: "gpt-4o-mini",
                                    total_tokens: 900, cost_usd: BigDecimal("0.0002"))
    end
  end

  test "skipped scenes and entries quoting another scene's opening are asked for again on their own" do
    scenes = beats + [ Beat.new(3, "Edison's company refused to pay him.", 10_000) ]
    first = { beats: [
      { beat: 1, opening: "Nikola Tesla was born", subject_type: "real_person", search_queries: [ "Nikola Tesla" ] },
      # Scene 3's words on scene 2: the answer merged beats and slid. Scene 3 is missing.
      { beat: 2, opening: "Edison's company refused to", subject_type: "real_person", search_queries: [ "Thomas Edison" ] }
    ] }
    second = { beats: [
      { beat: 2, opening: "He moved to New", subject_type: "real_place", search_queries: [ "New York 1884" ] },
      { beat: 3, opening: "Edison’s company refused to", subject_type: "real_person", search_queries: [ "Thomas Edison" ] }
    ] }
    generator = SequenceGenerator.new(first, second)

    result = Ai::ScenePlanner.new(generator: generator).call(topic: "Tesla", scenes: scenes)

    retry_prompt = generator.calls.second[:user_prompt]
    assert_no_match "Beat 1 ", retry_prompt
    assert_match "Beat 2 (10.0 s): He moved to New York.", retry_prompt
    assert_match "There are 2 beats: return 2 entries.", retry_prompt
    assert_equal [ "Nikola Tesla" ], result.plans[1].search_queries
    assert_equal [ "New York 1884" ], result.plans[2].search_queries
    assert_equal [ "Thomas Edison" ], result.plans[3].search_queries, "a curly apostrophe still matches"
    assert_equal 1800, result.total_tokens
    assert_equal BigDecimal("0.0004"), result.cost_usd
  end

  test "a full answer with matching openings is not asked for again" do
    answer = { beats: [ { beat: 1, opening: "Nikola Tesla was born" }, { beat: 2, opening: "He moved to New" } ] }
    generator = SequenceGenerator.new(answer)

    Ai::ScenePlanner.new(generator: generator).call(topic: "Tesla", scenes: beats)

    assert_equal 1, generator.calls.size
  end

  test "unknown subject types become generic_scene and queries are capped" do
    text = { beats: [ { beat: 1, subject_type: "spaceship", search_queries: %w[a b c d e] } ] }.to_json

    planner, = planner_for(text)
    plan = planner.call(topic: "Tesla", scenes: beats).plans[1]

    assert_equal "generic_scene", plan.subject_type
    assert_equal Ai::ScenePlanner::MAX_QUERIES, plan.search_queries.size
  end

  test "invalid JSON raises a clear error" do
    planner, = planner_for("not json at all")

    error = assert_raises(Ai::Error) { planner.call(topic: "Tesla", scenes: beats) }
    assert_equal "Scene planner returned invalid JSON", error.message
  end

  test "provider errors are passed through as Ai::Error" do
    planner, = planner_for(nil, error: Ai::Error.new("Text generation failed: quota"))

    assert_raises(Ai::Error) { planner.call(topic: "Tesla", scenes: beats) }
  end

  test "the estimate for a 5-minute script is well under a cent" do
    estimate = Ai::ScenePlanner.estimated_cost("word " * 750, 30)

    assert estimate > 0
    assert estimate < 0.01
  end

  test "reads how each beat may depict people, defaulting to normal" do
    text = { beats: [ { beat: 1, depiction: "no_face" }, { beat: 2, depiction: "something else" } ] }.to_json

    planner, generator = planner_for(text)
    plans = planner.call(topic: "Khalid ibn al-Walid", scenes: beats).plans

    assert_equal "no_face", plans[1].depiction
    assert_equal "normal", plans[2].depiction
    assert_includes generator.calls.first[:system_prompt], "\"no_figure\" for any scene that involves a prophet"
  end

  test "returns the video-wide depiction rule, defaulting to normal" do
    planner, = planner_for({ topic_depiction: "no_face", beats: [] }.to_json)
    assert_equal "no_face", planner.call(topic: "Khalid ibn al-Walid", scenes: beats).topic_depiction

    planner, = planner_for({ beats: [] }.to_json)
    assert_equal "normal", planner.call(topic: "Tides", scenes: beats).topic_depiction
  end

  test "reads topic and beat articles, cleaned up and capped" do
    text = {
      articles: [ "Prince Philip, Duke of Edinburgh", " HMS Calypso (D61) ", "", "HMS Calypso (D61)",
                  "Mon Repos, Corfu", "Corfu", "Princess Alice of Battenberg", "Prince Andrew of Greece and Denmark",
                  "Gordonstoun" ],
      beats: [ { beat: 1, articles: [ "HMS Calypso (D61)", "Corfu", "Greece" ] }, { beat: 2 } ]
    }.to_json

    planner, generator = planner_for(text)
    result = planner.call(topic: "Prince Philip", scenes: beats)

    assert_equal [ "Prince Philip, Duke of Edinburgh", "HMS Calypso (D61)", "Mon Repos, Corfu", "Corfu",
                   "Princess Alice of Battenberg", "Prince Andrew of Greece and Denmark" ], result.articles
    assert_equal [ "HMS Calypso (D61)", "Corfu" ], result.plans[1].articles
    assert_equal [], result.plans[2].articles
    assert_includes generator.calls.first[:system_prompt].squish, "Do not invent articles"
    assert_includes generator.calls.first[:system_prompt].squish, "name narrow articles"
    assert_includes generator.calls.first[:system_prompt], "'HMS Calypso (D61)'"
  end

  test "articles default to empty when the model leaves them out" do
    planner, = planner_for({ beats: [ { beat: 1, search_queries: [ "Corfu" ] } ] }.to_json)
    result = planner.call(topic: "Tides", scenes: beats)

    assert_equal [], result.articles
    assert_equal [], result.plans[1].articles
  end
end
