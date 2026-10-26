require "net/http"
require "json"

module Media
  # Fetches a JSON document over HTTPS. Shared by the image search services.
  # Backs off on HTTP 429 (rate limit) using the Retry-After header, up to MAX_ATTEMPTS.
  module HttpJson
    USER_AGENT = "Scenivora/0.1 (https://github.com/umarsabir12/scenivora; umarsabir1997@gmail.com)".freeze
    MAX_ATTEMPTS = 3
    MAX_WAIT_SECONDS = 30

    def self.get(url, params = {})
      uri = URI(url)
      uri.query = URI.encode_www_form(params) if params.any?

      response = fetch(uri)
      attempts = 1
      while response.code == "429" && attempts < MAX_ATTEMPTS
        sleep(retry_wait(response))
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

    def self.retry_wait(response)
      seconds = Integer(response["Retry-After"].to_s, exception: false) || 5
      [ seconds, MAX_WAIT_SECONDS ].min
    end
  end
end
