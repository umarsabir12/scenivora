module Ai
  # Raised by any AI provider service. Callers rescue this one class, whichever provider failed.
  class Error < StandardError
    MODERATION_BLOCKED = "the provider's safety check refused this prompt. Leave out real people's names " \
                         "and well-known characters or brands, then try again."

    # The provider's error as an Ai::Error, or as Ai::OutOfCredits when the provider account has no
    # credit left (OpenAI answers 429 with "insufficient_quota"). The message carries the provider's
    # own reason when it gave one, rather than only the HTTP status.
    def self.from(error, prefix)
      body = error.respond_to?(:response) && error.response.is_a?(Hash) ? error.response[:body] : nil
      details = provider_details(body)
      return OutOfCredits.new("#{prefix}: #{error.message}") if body.to_s.include?("insufficient_quota")
      return new("#{prefix}: #{MODERATION_BLOCKED}") if details["code"] == "moderation_blocked"

      new("#{prefix}: #{details['message'].presence || error.message}")
    end

    def self.provider_details(body)
      parsed = body.is_a?(String) ? JSON.parse(body) : body
      parsed.is_a?(Hash) && parsed["error"].is_a?(Hash) ? parsed["error"] : {}
    rescue JSON::ParserError
      {}
    end
    private_class_method :provider_details
  end
end
