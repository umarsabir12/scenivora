require "test_helper"

class Ai::TextGeneratorTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:response) do
    attr_reader :parameters

    def chat(parameters:)
      @parameters = parameters
      response
    end
  end

  RaisingClient = Object.new.tap do |client|
    def client.chat(parameters:)
      raise OpenAI::Error, "rate limited"
    end
  end

  def completion(content:, prompt_tokens: 1_000, completion_tokens: 500)
    {
      "choices" => [ { "message" => { "content" => content } } ],
      "usage" => {
        "prompt_tokens" => prompt_tokens,
        "completion_tokens" => completion_tokens,
        "total_tokens" => prompt_tokens + completion_tokens
      }
    }
  end

  test "returns the trimmed text with token usage and estimated cost" do
    client = FakeClient.new(completion(content: "  Hook line.\n\nMore narration.  "))

    result = Ai::TextGenerator.new(model: "gpt-4o-mini", client: client).call(
      system_prompt: "system", user_prompt: "user"
    )

    assert_equal "Hook line.\n\nMore narration.", result.text
    assert_equal "openai", result.provider
    assert_equal 1_500, result.total_tokens
    # 1,000 input tokens at $0.15/M + 500 output tokens at $0.60/M
    assert_equal BigDecimal("0.00045"), result.cost_usd
  end

  test "sends the system and user prompts as chat messages" do
    client = FakeClient.new(completion(content: "Narration"))

    Ai::TextGenerator.new(model: "gpt-4o-mini", client: client).call(
      system_prompt: "system prompt", user_prompt: "user prompt", temperature: 0.5
    )

    assert_equal "gpt-4o-mini", client.parameters[:model]
    assert_equal 0.5, client.parameters[:temperature]
    assert_equal [ { role: "system", content: "system prompt" }, { role: "user", content: "user prompt" } ],
      client.parameters[:messages]
  end

  test "wraps provider errors in its own error class" do
    error = assert_raises(Ai::TextGenerator::Error) do
      Ai::TextGenerator.new(client: RaisingClient).call(system_prompt: "s", user_prompt: "u")
    end

    assert_match "rate limited", error.message
  end

  test "raises when the provider returns no text" do
    client = FakeClient.new(completion(content: "   "))

    assert_raises(Ai::TextGenerator::Error) do
      Ai::TextGenerator.new(client: client).call(system_prompt: "s", user_prompt: "u")
    end
  end

  test "raises a clear error when the API key is missing" do
    original = ENV.delete("OPENAI_API_KEY")

    error = assert_raises(Ai::TextGenerator::Error) do
      Ai::TextGenerator.new.call(system_prompt: "s", user_prompt: "u")
    end

    assert_match "OPENAI_API_KEY", error.message
  ensure
    ENV["OPENAI_API_KEY"] = original if original
  end
end
