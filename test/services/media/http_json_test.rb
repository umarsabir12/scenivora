require "test_helper"

class Media::HttpJsonTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :headers) do
    def [](name)
      headers[name]
    end
  end

  test "retries rate limits and server errors, not other failures" do
    assert Media::HttpJson.retryable?(Response.new("429", {}))
    assert Media::HttpJson.retryable?(Response.new("500", {}))
    assert Media::HttpJson.retryable?(Response.new("503", {}))
    assert_not Media::HttpJson.retryable?(Response.new("404", {}))
    assert_not Media::HttpJson.retryable?(Response.new("200", {}))
  end

  test "waits as long as Retry-After says, up to a cap, or backs off when it is missing" do
    assert_equal 7, Media::HttpJson.retry_wait(Response.new("429", { "Retry-After" => "7" }))
    assert_equal Media::HttpJson::MAX_WAIT_SECONDS, Media::HttpJson.retry_wait(Response.new("429", { "Retry-After" => "999" }))
    assert_equal 2, Media::HttpJson.retry_wait(Response.new("500", {}), 1)
    assert_equal 4, Media::HttpJson.retry_wait(Response.new("500", {}), 2)
  end
end
