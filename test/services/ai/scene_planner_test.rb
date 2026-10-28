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

  test "a scene the model skipped gets an empty plan" do
    text = { beats: [ { beat: 1, search_queries: [ "Tesla" ] } ] }.to_json

    planner, = planner_for(text)
    result = planner.call(topic: "Tesla", scenes: beats)

    assert_equal [], result.plans[2].search_queries
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
end
