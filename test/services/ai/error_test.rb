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
end
