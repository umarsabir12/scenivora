module Ai
  # Raised by any AI provider service. Callers rescue this one class, whichever provider failed.
  class Error < StandardError
    # The provider's error as an Ai::Error, or as Ai::OutOfCredits when the provider account has no
    # credit left (OpenAI answers 429 with "insufficient_quota").
    def self.from(error, prefix)
      body = error.respond_to?(:response) && error.response.is_a?(Hash) ? error.response[:body].to_s : ""
      (body.include?("insufficient_quota") ? OutOfCredits : self).new("#{prefix}: #{error.message}")
    end
  end
end
