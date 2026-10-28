require "test_helper"

class Ai::MetadataGeneratorTest < ActiveSupport::TestCase
  class FakeGenerator
    attr_reader :args

    def initialize(text)
      @text = text
    end

    def call(**args)
      @args = args
      Ai::TextGenerator::Result.new(text: @text, provider: "openai", model: "gpt-4o-mini", total_tokens: 900, cost_usd: BigDecimal("0.0003"))
    end
  end

  def generate(payload)
    generator = FakeGenerator.new(payload.is_a?(String) ? payload : payload.to_json)
    [ Ai::MetadataGenerator.new(generator: generator).call(topic: "Tides", tone: "documentary", script: "The sea rises."), generator ]
  end

  test "returns the title, description, tags and category, asking for JSON" do
    result, generator = generate(title: "Why the Sea Rises Twice a Day", description: "A hook.\n\nWhat we cover.",
                                 tags: [ "tides", "moon", "ocean science" ], category: "Science & Technology")

    assert_equal true, generator.args[:json]
    assert_equal "Why the Sea Rises Twice a Day", result.title
    assert_equal [ "tides", "moon", "ocean science" ], result.tags
    assert_equal "Science & Technology", result.category
    assert_equal 900, result.total_tokens
  end

  test "cleans tags, caps the title, and falls back to a known category" do
    result, = generate(title: "x" * 150, description: "d", tags: [ "#tides", "Tides", "a" * 40, "moon, sun", "" ],
                       category: "Space Lasers")

    assert_equal 100, result.title.length
    assert_equal [ "tides", "moon sun" ], result.tags
    assert_equal "Education", result.category
  end

  test "invalid JSON raises a clear error" do
    assert_raises(Ai::Error) { generate("not json") }
  end
end
