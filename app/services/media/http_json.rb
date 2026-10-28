require "net/http"
require "json"

module Media
  # Fetches a JSON document over HTTPS. Shared by the image search services.
  # Retries rate limits (429) and server errors (5xx) with backoff, up to MAX_ATTEMPTS. Uses the
  # Retry-After header when the server sends one.
  module HttpJson
    USER_AGENT = "Scenivora/0.1 (https://github.com/umarsabir12/scenivora; umarsabir1997@gmail.com)".freeze
    MAX_ATTEMPTS = 3
    MAX_WAIT_SECONDS = 30

    def self.get(url, params = {})
      uri = URI(url)
      uri.query = URI.encode_www_form(params) if params.any?

      response = fetch(uri)
      attempts = 1
      while retryable?(response) && attempts < MAX_ATTEMPTS
        sleep(retry_wait(response, attempts))
        response = fetch(uri)
        attempts += 1
      end
      raise Media::Error, "#{uri.host} responded with #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError => e
      raise Media::Error, "#{uri.host} could not be used: #{e.message}"
    end

    def self.fetch(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
        http.request(Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT))
      end
    end

    def self.retryable?(response)
      response.code == "429" || response.code.start_with?("5")
    end

    # Retry-After if given, otherwise 2, then 4 seconds.
    def self.retry_wait(response, attempts = 1)
      seconds = Integer(response["Retry-After"].to_s, exception: false) || 2**attempts
      [ seconds, MAX_WAIT_SECONDS ].min
    end
  end
end
