require "test_helper"

class Ai::ErrorTest < ActiveSupport::TestCase
  def provider_error(body)
    Faraday::TooManyRequestsError.new("the server responded with status 429", { status: 429, body: body })
  end

  test "a provider account with no credit left becomes OutOfCredits" do
    error = Ai::Error.from(provider_error('{"error": {"type": "insufficient_quota", "code": "credit_balance_exhausted"}}'),
                           "Text generation failed")

    assert_kind_of Ai::OutOfCredits, error
    assert_kind_of Ai::Error, error, "callers that rescue Ai::Error still catch it"
    assert_equal "Text generation failed: the server responded with status 429", error.message
  end

  test "a plain rate limit or other failure stays an Ai::Error" do
    assert_instance_of Ai::Error, Ai::Error.from(provider_error('{"error": {"type": "rate_limit_exceeded"}}'), "Research call failed")
    assert_instance_of Ai::Error, Ai::Error.from(OpenAI::Error.new("boom"), "Research call failed")
  end

  test "the provider's own reason replaces the bare HTTP status" do
    error = Faraday::BadRequestError.new("the server responded with status 400",
                                         { status: 400, body: '{"error": {"message": "Invalid size \'99x99\'.", "code": null}}' })

    assert_equal "Image generation failed: Invalid size '99x99'.", Ai::Error.from(error, "Image generation failed").message
  end

  test "a prompt refused by the safety check says what to change" do
    error = Faraday::BadRequestError.new("the server responded with status 400",
                                         { status: 400, body: { "error" => { "code" => "moderation_blocked", "message" => "Your request was rejected by the safety system." } } })

    message = Ai::Error.from(error, "Image generation failed").message
    assert_match "safety check refused this prompt", message
    assert_match "real people's names", message
  end

  test "a body that isn't JSON falls back to the HTTP status" do
    error = Faraday::BadRequestError.new("the server responded with status 400", { status: 400, body: "<html>Bad gateway</html>" })

    assert_equal "Speech generation failed: the server responded with status 400", Ai::Error.from(error, "Speech generation failed").message
  end
end
