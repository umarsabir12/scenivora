# Shared OpenAI client configuration (ruby-openai gem).
# Build clients with OpenAI::Client.new(access_token: ...) or use the
# ENV["OPENAI_API_KEY"] default via OpenAI.configure below.
OpenAI.configure do |config|
  config.access_token = ENV["OPENAI_API_KEY"]
  config.request_timeout = 120
end
