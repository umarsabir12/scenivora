require "test_helper"

class Ai::ImageVerifierTest < ActiveSupport::TestCase
  class FakeGenerator
    attr_reader :args, :calls

    # fail_with_more_than: fails any call showing more images than this, like a provider timeout.
    def initialize(text, fail_with_more_than: nil)
      @text = text
      @fail_with_more_than = fail_with_more_than
      @calls = []
    end

    def call(**args)
      @calls << args
      @args = args
      raise Ai::Error, "OpenAI request timed out" if @fail_with_more_than && args[:images].size > @fail_with_more_than

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
    @candidates = %w[Wright_Flyer_1903.jpg Memorial_2013.jpg Cyclone.jpg Kitty_Hawk.jpg Glider_1902.jpg Orville.jpg
                     Extra.jpg].map do |name|
      @scene.images.create!(provider: "wikimedia_commons", image_url: "https://upload.wikimedia.org/#{name}",
                            page_url: "https://commons.wikimedia.org/wiki/File:#{name}", credit: "x", license: "CC0", taken_on: "1903")
    end
  end

  def verify(text, previews: FakePreviews.new, generator: FakeGenerator.new(text))
    [ Ai::ImageVerifier.new(generator: generator, previews: previews).call(scene: @scene, candidates: @candidates), generator ]
  end

  test "shows up to six previews in one call and returns the chosen candidate" do
    result, generator = verify({ choice: "F", reason: "Shows the 1903 flight." }.to_json)

    assert_equal @candidates[5].id, result.choice_id
    assert_equal "Shows the 1903 flight.", result.reason
    assert_equal 1, generator.calls.size
    assert_equal 6, generator.args[:images].size
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
    assert_equal @candidates[1..6].map { |media| "jpeg-#{media.id}" }, generator.args[:images]
  end

  test "a letter beyond the pictures shown counts as no choice" do
    @candidates = @candidates.first(2)

    result, = verify({ choice: "E" }.to_json)

    assert_nil result.choice_id
  end

  test "when the six-picture check fails, the first three are checked on their own" do
    generator = FakeGenerator.new({ choice: "C", reason: "Shows the flight." }.to_json, fail_with_more_than: 3)

    result, = verify(nil, generator: generator)

    assert_equal [ 6, 3 ], generator.calls.map { |args| args[:images].size }
    assert_equal @candidates[2].id, result.choice_id
    assert_not_includes generator.args[:user_prompt], "D: "
  end

  test "a failed check of three or fewer pictures is not retried" do
    @candidates = @candidates.first(3)
    generator = FakeGenerator.new({ choice: "A" }.to_json, fail_with_more_than: 0)

    assert_raises(Ai::Error) { verify(nil, generator: generator) }
    assert_equal 1, generator.calls.size
  end

  test "names the Wikipedia article a picture comes from" do
    @candidates.first.update!(source_article: "Wright Flyer")

    _result, generator = verify({ choice: "A" }.to_json)

    assert_includes generator.args[:user_prompt], "A: [image] Wright Flyer 1903 (taken 1903) (from the Wikipedia article \"Wright Flyer\")"
  end

  test "raises when nothing could be previewed" do
    all = @candidates.map(&:id)

    assert_raises(Ai::Error) { verify({ choice: "A" }.to_json, previews: FakePreviews.new(skip: all)) }
  end

  test "tells the check when a scene must not show a revered figure's face" do
    @scene.update!(plan: @scene.plan.merge("depiction" => "no_face"))

    _result, generator = verify({ choice: nil }.to_json)

    assert_includes generator.args[:user_prompt], "Reject any picture that shows this person's face"
  end

  test "reports whether the chosen picture shows faces" do
    result, = verify({ choice: "A", faces: true, reason: "A painted battle with warriors' faces." }.to_json)
    assert result.faces

    result, = verify({ choice: "A", reason: "A map." }.to_json)
    assert_not result.faces
  end
end
