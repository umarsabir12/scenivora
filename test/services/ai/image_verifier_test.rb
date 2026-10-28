require "test_helper"

class Ai::ImageVerifierTest < ActiveSupport::TestCase
  class FakeGenerator
    attr_reader :args

    def initialize(text)
      @text = text
    end

    def call(**args)
      @args = args
      Ai::TextGenerator::Result.new(text: @text, provider: "openai", model: "gpt-4o-mini", total_tokens: 1_500, cost_usd: BigDecimal("0.0004"))
    end
  end

  # Returns fake JPEG bytes, or nil (no preview) for the ids it is told to skip.
  class FakePreviews
    def initialize(skip: [])
      @skip = skip
    end

    def jpeg(media)
      "jpeg-#{media.id}" unless @skip.include?(media.id)
    end
  end

  setup do
    project = users(:one).projects.create!(prompt: "The Wright brothers", tone: "documentary", target_length_minutes: 3)
    @scene = project.scenes.create!(position: 1, text: "On December 17, 1903, the Flyer lifted off.", start_ms: 0, duration_ms: 10_000,
                                    plan: { "visual_intent" => "The Wright Flyer taking off in 1903" })
    @candidates = %w[Wright_Flyer_1903.jpg Memorial_2013.jpg Cyclone.jpg Extra.jpg].map do |name|
      @scene.images.create!(provider: "wikimedia_commons", image_url: "https://upload.wikimedia.org/#{name}",
                            page_url: "https://commons.wikimedia.org/wiki/File:#{name}", credit: "x", license: "CC0", taken_on: "1903")
    end
  end

  def verify(text, previews: FakePreviews.new)
    generator = FakeGenerator.new(text)
    [ Ai::ImageVerifier.new(generator: generator, previews: previews).call(scene: @scene, candidates: @candidates), generator ]
  end

  test "shows up to three previews with the scene and returns the chosen candidate" do
    result, generator = verify({ choice: "B", reason: "Shows the 1903 flight." }.to_json)

    assert_equal @candidates[1].id, result.choice_id
    assert_equal "Shows the 1903 flight.", result.reason
    assert_equal 3, generator.args[:images].size
    assert_equal true, generator.args[:json]
    assert_includes generator.args[:user_prompt], "Should show: The Wright Flyer taking off in 1903"
    assert_includes generator.args[:user_prompt], "B: [image] Memorial 2013 (taken 1903)"
  end

  test "no choice means no candidate fits" do
    result, = verify({ choice: nil, reason: "None show the flight." }.to_json)

    assert_nil result.choice_id
  end

  test "candidates without a preview are skipped, and letters follow what was shown" do
    result, generator = verify({ choice: "A" }.to_json, previews: FakePreviews.new(skip: [ @candidates[0].id ]))

    assert_equal @candidates[1].id, result.choice_id
    assert_equal [ "jpeg-#{@candidates[1].id}", "jpeg-#{@candidates[2].id}", "jpeg-#{@candidates[3].id}" ], generator.args[:images]
  end

  test "raises when nothing could be previewed" do
    all = @candidates.map(&:id)

    assert_raises(Ai::Error) { verify({ choice: "A" }.to_json, previews: FakePreviews.new(skip: all)) }
  end
end
