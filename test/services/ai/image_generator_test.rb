require "test_helper"

class Ai::ImageGeneratorTest < ActiveSupport::TestCase
  class FakeImages
    attr_reader :parameters

    def initialize(response: nil, error: nil)
      @response = response
      @error = error
    end

    def generate(parameters:)
      @parameters = parameters
      raise @error if @error

      @response
    end
  end

  FakeClient = Struct.new(:images)

  PNG = "\x89PNG fake bytes".b

  def response(usage: { "input_tokens" => 100, "input_tokens_details" => { "text_tokens" => 100, "image_tokens" => 0 },
                        "output_tokens" => 1_000 })
    { "data" => [ { "b64_json" => Base64.strict_encode64(PNG) } ], "usage" => usage }
  end

  def generator_with(images)
    Ai::ImageGenerator.new(model: "gpt-image-1-mini", client: FakeClient.new(images))
  end

  test "returns the decoded image and the cost from the token usage" do
    result = generator_with(FakeImages.new(response: response)).call(prompt: "An empty boxing gym at dawn")

    assert_equal PNG, result.image
    assert_equal "image/png", result.content_type
    # 100 text tokens at $2.00/M + 1,000 image tokens at $8.00/M
    assert_equal BigDecimal("0.0082"), result.cost_usd
  end

  test "sends the model, a landscape size, and the prompt with the safety rules" do
    images = FakeImages.new(response: response)

    generator_with(images).call(prompt: "An empty boxing gym at dawn")

    assert_equal "gpt-image-1-mini", images.parameters[:model]
    assert_equal "1536x1024", images.parameters[:size]
    assert images.parameters[:prompt].start_with?("An empty boxing gym at dawn")
    assert_includes images.parameters[:prompt], "Do not show a recognizable face"
  end

  test "an empty response raises a clear error" do
    images = FakeImages.new(response: { "data" => [] })

    error = assert_raises(Ai::Error) { generator_with(images).call(prompt: "x") }
    assert_equal "Provider returned no image", error.message
  end

  test "provider errors become Ai::Error" do
    images = FakeImages.new(error: Faraday::BadRequestError.new("rejected by safety system"))

    assert_raises(Ai::Error) { generator_with(images).call(prompt: "x") }
  end

  test "illustration style asks for a painting, not a photo" do
    images = FakeImages.new(response: response)

    generator_with(images).call(prompt: "Jinnah addressing a crowd in 1940", style: "illustration")

    assert_includes images.parameters[:prompt], "oil-painting style"
    assert_includes images.parameters[:prompt], "never a photograph"
    assert_not_includes images.parameters[:prompt], "Photorealistic"
  end

  test "an unknown style is refused" do
    assert_raises(ArgumentError) { generator_with(FakeImages.new(response: response)).call(prompt: "x", style: "3d") }
  end
end
