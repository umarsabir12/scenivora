require "test_helper"

class Ai::CandidateRankerTest < ActiveSupport::TestCase
  class FakeGenerator
    attr_reader :args

    def initialize(text)
      @text = text
    end

    def call(**args)
      @args = args
      Ai::TextGenerator::Result.new(text: @text, provider: "openai", model: "gpt-4o-mini", total_tokens: 1_200, cost_usd: BigDecimal("0.0003"))
    end
  end

  setup do
    project = users(:one).projects.create!(prompt: "The Wright brothers", tone: "documentary", target_length_minutes: 3)
    @scene = project.scenes.create!(position: 1, text: "In 1903 the Flyer lifted off.", start_ms: 0, duration_ms: 10_000,
                                    plan: { "visual_intent" => "The 1903 Wright Flyer in the air" })
    @flyer = @scene.images.create!(provider: "wikimedia_commons", image_url: "https://upload.wikimedia.org/a.jpg",
                                   page_url: "https://commons.wikimedia.org/wiki/File:1903_Wright_Flyer_first_flight.jpg", credit: "x", license: "CC0")
    @cyclone = @scene.images.create!(provider: "wikimedia_commons", image_url: "https://upload.wikimedia.org/b.jpg",
                                     page_url: "https://commons.wikimedia.org/wiki/File:Cyclone_Favio_21_February_2007.jpg", credit: "x", license: "CC0")
  end

  def rank(text)
    generator = FakeGenerator.new(text)
    [ Ai::CandidateRanker.new(generator: generator).call(topic: "The Wright brothers", scenes: [ @scene.reload ]), generator ]
  end

  test "sends the scene intent and each candidate's readable title, and asks for JSON" do
    _result, generator = rank({ scenes: [] }.to_json)

    assert_equal true, generator.args[:json]
    assert_includes generator.args[:user_prompt], "Scene 1: The 1903 Wright Flyer in the air"
    assert_includes generator.args[:user_prompt], "#{@flyer.id} [image] 1903 Wright Flyer first flight"
    assert_includes generator.args[:user_prompt], "#{@cyclone.id} [image] Cyclone Favio 21 February 2007"
  end

  test "returns the kept ids per scene, ignoring ids that aren't the scene's" do
    result, = rank({ scenes: [ { scene: 1, keep: [ @flyer.id, 999_999, @flyer.id ] } ] }.to_json)

    assert_equal({ 1 => [ @flyer.id ] }, result.kept)
    assert_equal 1_200, result.total_tokens
  end

  test "a scene the model leaves out keeps nothing" do
    result, = rank({ scenes: [] }.to_json)

    assert_equal({ 1 => [] }, result.kept)
  end

  test "invalid JSON raises a clear error" do
    assert_raises(Ai::Error) { rank("nope") }
  end
end
