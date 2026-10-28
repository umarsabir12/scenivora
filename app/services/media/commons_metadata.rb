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

    def self.text(html)
      ActionController::Base.helpers.strip_tags(html.to_s).squish
    end
  end
end
