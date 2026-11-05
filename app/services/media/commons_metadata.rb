module Media
  # Reads the human-written parts of a Wikimedia file's metadata: what it shows, when it was made,
  # and its categories. They let the relevance check judge more than a file name.
  module CommonsMetadata
    MAX_DESCRIPTION = 300
    MAX_CATEGORIES = 8

    def self.details(meta)
      {
        description: text(meta.dig("ImageDescription", "value")).first(MAX_DESCRIPTION).presence,
        taken_on: text(meta.dig("DateTimeOriginal", "value")).first(40).presence,
        categories: meta.dig("Categories", "value").to_s.split("|").map(&:strip).reject(&:empty?)
                        .first(MAX_CATEGORIES).join(", ").presence
      }
    end

    # Who made the file. An author given only as a numbered link ("[1]", pointing at a Flickr
    # account) is named after the link instead, else left to the caller's default.
    def self.artist(meta)
      html = meta.dig("Artist", "value").to_s
      name = text(html)
      return name unless name.empty? || name.match?(/\A[\[\]\d\s,]+\z/)

      account = html[%r{flickr\.com/photos/([^/"]+)}, 1]
      account && "#{CGI.unescape(account)} on Flickr"
    end

    def self.text(html)
      ActionController::Base.helpers.strip_tags(html.to_s).squish
    end
  end
end
