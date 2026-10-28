require "net/http"

module Media
  # Downloads a file over HTTPS to a local path. Follows redirects, backs off on HTTP 429,
  # and stops when the file is larger than `max_bytes`.
  module Download
    MAX_REDIRECTS = 3

    def self.to_file(url, path, max_bytes:, redirects: 0, attempts: 1)
      uri = URI(url)
      raise Media::Error, "Only HTTPS downloads are allowed" unless uri.is_a?(URI::HTTPS)

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) do |http|
        http.request(Net::HTTP::Get.new(uri, "User-Agent" => HttpJson::USER_AGENT)) do |response|
          case response
          when Net::HTTPRedirection
            raise Media::Error, "Too many redirects from #{uri.host}" if redirects >= MAX_REDIRECTS

            return to_file(URI.join(url, response["location"]).to_s, path, max_bytes: max_bytes, redirects: redirects + 1)
          when Net::HTTPTooManyRequests, Net::HTTPServerError
            raise Media::Error, "#{uri.host} responded with #{response.code}" if attempts >= HttpJson::MAX_ATTEMPTS

            sleep(HttpJson.retry_wait(response, attempts))
            return to_file(url, path, max_bytes: max_bytes, redirects: redirects, attempts: attempts + 1)
          when Net::HTTPSuccess
            write_body(response, path, max_bytes)
          else
            raise Media::Error, "#{uri.host} responded with #{response.code}"
          end
        end
      end
      path
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
      raise Media::Error, "#{uri&.host} could not be used: #{e.message}"
    end

    def self.write_body(response, path, max_bytes)
      written = 0
      File.open(path, "wb") do |file|
        response.read_body do |chunk|
          written += chunk.bytesize
          raise Media::Error, "File is larger than #{max_bytes / 1.megabyte} MB" if written > max_bytes

          file.write(chunk)
        end
      end
    end
  end
end
