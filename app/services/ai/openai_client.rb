module Ai
  # Builds the OpenAI API client shared by the text and speech services.
  module OpenaiClient
    REQUEST_TIMEOUT_SECONDS = 120

    def self.build
      OpenAI::Client.new(
        access_token: ENV["OPENAI_API_KEY"].presence || raise(Ai::Error, "OPENAI_API_KEY is not set"),
        request_timeout: REQUEST_TIMEOUT_SECONDS
      )
    end
  end
end
