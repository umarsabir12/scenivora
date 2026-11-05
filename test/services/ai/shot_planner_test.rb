require "test_helper"

class Ai::ShotPlannerTest < ActiveSupport::TestCase
  class FakeGenerator
    attr_reader :args

    def initialize(shots)
      @shots = shots
    end

    def call(**args)
      @args = args
      Ai::ResearchGenerator::Result.new(text: "```json\n#{{ shots: @shots }.to_json}\n```", provider: "openai", model: "gpt-5-mini",
                                        total_tokens: 9_000, cost_usd: BigDecimal("0.02"), searches: 0)
    end
  end

  CATALOG = [
    { "id" => "m1", "shows" => "Ronaldo heading the ball in Portugal kit", "year" => "2016", "people" => [ "Cristiano Ronaldo" ], "usable" => true },
    { "id" => "m2", "shows" => "Coach at a press conference", "year" => "2022", "people" => [ "Jorge Jesus" ], "usable" => true },
    { "id" => "m3", "shows" => "Federation crest", "usable" => false }
  ].freeze

  PARAGRAPHS = [ "The Euro 2016 final.", "Jorge Jesus took over.", "Ronaldo left the camp.", "He posted his goodbye." ].freeze

  def plan(shots, max_ai_images: 8)
    generator = FakeGenerator.new(shots)
    [ Ai::ShotPlanner.new(generator: generator).call(paragraphs: PARAGRAPHS, catalog: CATALOG, max_ai_images: max_ai_images), generator ]
  end

  test "gives each paragraph its catalog pictures, or an AI prompt, with the cost" do
    result, generator = plan([ { paragraph: 1, pictures: [ "m1" ], ai_prompt: nil }, { paragraph: 2, pictures: [ "m2" ] },
                               { paragraph: 3, pictures: [], ai_prompt: "A hotel corridor at dusk, a figure seen from behind." },
                               { paragraph: 4, pictures: [], ai_prompt: "A phone glowing on a bench." } ])

    assert_equal [ [ "m1" ], [ "m2" ], [], [] ], result.shots.map { |shot| shot.pictures.map { |picture| picture["id"] } }
    assert_equal "A hotel corridor at dusk, a figure seen from behind.", result.shots.third.ai_prompt
    assert_equal "Jorge Jesus took over.", result.shots.second.text
    assert_equal BigDecimal("0.02"), result.cost_usd

    assert_includes generator.args[:input], "2. Jorge Jesus took over."
    assert_includes generator.args[:input], "m2: Coach at a press conference (2022) [Jorge Jesus]"
    assert_not_includes generator.args[:input], "m3:"
    assert_includes generator.args[:instructions], "At most 8 paragraphs get an AI image"
  end

  test "drops unknown, unusable and repeated pictures, and caps the AI images" do
    result, = plan([ { paragraph: 1, pictures: [ "m1", "m9", "m3" ] }, { paragraph: 2, pictures: [ "m1" ], ai_prompt: "A press room." },
                     { paragraph: 3, ai_prompt: "A corridor." }, { paragraph: 4, ai_prompt: "A phone." } ], max_ai_images: 2)

    assert_equal %w[m9 m3 m1], result.dropped
    assert_equal [ nil, "A press room.", "A corridor.", nil ], result.shots.map(&:ai_prompt)
    assert_empty result.shots.second.pictures
  end

  test "an answer without shots is an error" do
    generator = Struct.new(:text) do
      def call(**) = Ai::ResearchGenerator::Result.new(text: text, provider: "openai", model: "gpt-5-mini", total_tokens: 1,
                                                       cost_usd: 0, searches: 0)
    end

    assert_raises(Ai::Error) do
      Ai::ShotPlanner.new(generator: generator.new("no json")).call(paragraphs: PARAGRAPHS, catalog: CATALOG, max_ai_images: 8)
    end
  end
end
