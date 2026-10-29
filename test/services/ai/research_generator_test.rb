require "test_helper"

class Ai::ResearchGeneratorTest < ActiveSupport::TestCase
  class FakeResponses
    attr_reader :parameters

    def initialize(response)
      @response = response
    end

    def create(parameters:)
      @parameters = parameters
      @response
    end
  end

  FakeClient = Struct.new(:responses)

  def response
    { "output" => [
        { "type" => "reasoning" },
        { "type" => "web_search_call", "action" => { "type" => "search" } },
        { "type" => "web_search_call", "action" => { "type" => "open_page" } },
        { "type" => "message", "content" => [ { "type" => "output_text", "text" => "{\"beats\": []}" } ] }
      ],
      "usage" => { "input_tokens" => 20_000, "output_tokens" => 4_000, "total_tokens" => 24_000 } }
  end

  test "searches only the given domains, and counts searches and tokens in the cost" do
    responses = FakeResponses.new(response)
    result = Ai::ResearchGenerator.new(model: "gpt-5.5", client: FakeClient.new(responses))
                                   .call(instructions: "Research", input: "Topic", domains: [ "en.wikipedia.org" ], max_searches: 5)

    assert_equal "{\"beats\": []}", result.text
    assert_equal 2, result.searches
    assert_equal 24_000, result.total_tokens
    # 20k input at $5/M + 4k output at $30/M + 2 searches at $0.01
    assert_equal BigDecimal("0.24"), result.cost_usd
    assert_equal [ { type: "web_search", filters: { allowed_domains: [ "en.wikipedia.org" ] } } ], responses.parameters[:tools]
    assert_equal 5, responses.parameters[:max_tool_calls]
    assert_equal({ effort: "medium" }, responses.parameters[:reasoning])
  end

  test "models that don't reason get no reasoning setting" do
    responses = FakeResponses.new(response)
    Ai::ResearchGenerator.new(model: "gpt-4.1", client: FakeClient.new(responses)).call(instructions: "R", input: "T", domains: [])

    assert_nil responses.parameters[:reasoning]
  end

  test "without domains it doesn't search, and shows pictures after the text" do
    responses = FakeResponses.new(response)
    Ai::ResearchGenerator.new(model: "gpt-5.5", client: FakeClient.new(responses))
                         .call(instructions: "Review", input: "Storyboard", images: [ "jpeg-1" ], effort: "low")

    assert_nil responses.parameters[:tools]
    assert_nil responses.parameters[:max_tool_calls]
    content = responses.parameters[:input].first[:content]
    assert_equal({ type: "input_text", text: "Storyboard" }, content.first)
    assert_equal "data:image/jpeg;base64,#{Base64.strict_encode64("jpeg-1")}", content.second[:image_url]
    assert_equal "low", content.second[:detail]
    assert_equal({ effort: "low" }, responses.parameters[:reasoning])
  end

  test "an answer without text is an error" do
    client = FakeClient.new(FakeResponses.new({ "output" => [ { "type" => "web_search_call" } ], "usage" => {} }))

    assert_raises(Ai::Error) { Ai::ResearchGenerator.new(model: "gpt-5.5", client: client).call(instructions: "R", input: "T", domains: []) }
  end
end
