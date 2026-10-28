require "test_helper"

class Ai::QueryRewriterTest < ActiveSupport::TestCase
  class FakeGenerator
    attr_reader :args

    def initialize(text)
      @text = text
    end

    def call(**args)
      @args = args
      Ai::TextGenerator::Result.new(text: @text, provider: "openai", model: "gpt-4o-mini", total_tokens: 400, cost_usd: BigDecimal("0.0001"))
    end
  end

  setup do
    project = users(:one).projects.create!(prompt: "The Panama Canal", tone: "documentary", target_length_minutes: 3)
    @scene = project.scenes.create!(position: 6, text: "Workers dug, blasted, and moved earth.", start_ms: 0, duration_ms: 10_000,
                                    plan: { "visual_intent" => "Digging the canal", "search_queries" => [ "Panama Canal workers digging" ] })
  end

  def rewrite(payload)
    generator = FakeGenerator.new(payload.to_json)
    [ Ai::QueryRewriter.new(generator: generator).call(topic: "The Panama Canal", scenes: [ @scene ]), generator ]
  end

  test "sends the failed queries and returns new ones per scene, capped at four" do
    result, generator = rewrite(scenes: [ { scene: 6, queries: [ "Culebra Cut steam shovel", " Culebra Cut 1910 ", "", "a", "b", "c" ] } ])

    assert_includes generator.args[:user_prompt], "Failed queries: Panama Canal workers digging"
    assert_equal({ 6 => [ "Culebra Cut steam shovel", "Culebra Cut 1910", "a", "b" ] }, result.queries)
  end

  test "a scene the model skipped gets no new queries" do
    result, = rewrite(scenes: [])

    assert_equal({ 6 => [] }, result.queries)
  end
end
