module Ai
  # Looks at every picture in a video's library before the script is written and says what each one
  # really shows, so the script and the shot list can be built from pictures that exist. Commons
  # titles and categories are often wrong or vague ("Real Madrid vs. Atlético 2013 Set B 19", a
  # whole tournament category that holds the referees); a look is what tells a celebration from a
  # crowd. Pictures go in batches of BATCH_SIZE small previews, each labelled with its id.
  class MediaCatalog
    # entries: [Entry]. failed: ids that couldn't be previewed or described.
    Result = Data.define(:entries, :failed, :total_tokens, :cost_usd)
    # kind: one of KINDS. usable: false for logos, text pages, watermarks and pictures off the topic.
    Entry = Data.define(:id, :item, :shows, :people, :year, :kind, :usable)

    PROVIDER = "openai".freeze
    DEFAULT_MODEL = "gpt-5-mini".freeze
    PRICING_PER_MILLION = Ai::PictureScout::PRICING_PER_MILLION
    BATCH_SIZE = 16
    # Wikimedia serves thumbnails in fixed steps; this one is enough for a low-detail look.
    THUMB_WIDTH = 330
    KINDS = %w[action celebration portrait group crowd stadium trophy place object document logo other].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You catalog the pictures a documentary video can use. You get the video's topic, then pictures
      labelled with an id, their file title and, when known, the date taken. For each picture say
      what a viewer actually sees, judged from the picture first and the title second.

      Return only JSON:
      {"pictures": [{"id": "<id>",
                     "shows": "<what is visible, at most 20 words: who or what, doing what, where>",
                     "people": ["<names, only when the title or caption names them>"],
                     "year": "<year taken or shown, from the date or title, or null>",
                     "kind": "action" | "celebration" | "portrait" | "group" | "crowd" | "stadium" | "trophy" |
                             "place" | "object" | "document" | "logo" | "other",
                     "usable": <false when it is a logo, mostly text, watermarked, blurry, graphic,
                                or has nothing to do with the topic>}]}
      Describe every id you were given, in order. You cannot recognise people from their faces:
      name people only from the title or caption.
    PROMPT

    def initialize(previews: Media::PreviewFetcher.new, model: ENV.fetch("OPENAI_CATALOG_MODEL", DEFAULT_MODEL), client: nil)
      @previews = previews
      @model = model
      @client = client
    end

    # items: ImageResults. Ids are "m1", "m2", ... in the order given.
    def call(topic:, items:)
      @usage = { input: 0, output: 0, total: 0 }
      labelled = items.each_with_index.map { |item, index| [ "m#{index + 1}", item ] }
      entries = []
      failed = []
      labelled.each_slice(BATCH_SIZE) do |batch|
        shown = batch.filter_map { |id, item| (jpeg = preview(item)) ? [ id, item, jpeg ] : (failed << id && nil) }
        next if shown.empty?

        described = describe(topic, shown)
        shown.each do |id, item, _|
          data = described[id]
          data ? entries << entry(id, item, data) : failed << id
        end
      end
      Result.new(entries: entries, failed: failed, total_tokens: @usage[:total], cost_usd: cost)
    rescue OpenAI::Error, Faraday::Error => e
      raise Ai::Error.from(e, "Media catalog failed")
    end

    # A Wikimedia file's small thumbnail, or the URL as it is for other sources.
    def self.thumb_url(url)
      url = url.to_s.sub(/\?.*\z/, "")
      if url.include?("/commons/thumb/")
        url.sub(%r{/\d+px-([^/]+)\z}, "/#{THUMB_WIDTH}px-\\1")
      elsif (match = url.match(%r{\Ahttps://upload\.wikimedia\.org/wikipedia/commons/(\h/\h\h)/([^/]+)\z}))
        name = match[2]
        name += ".jpg" if name.match?(/\.(tiff?|pdf)\z/i)
        name += ".png" if name.match?(/\.svg\z/i)
        "https://upload.wikimedia.org/wikipedia/commons/thumb/#{match[1]}/#{match[2]}/#{THUMB_WIDTH}px-#{name}"
      else
        url
      end
    end

    private
      attr_reader :model

      def client
        @client ||= Ai::OpenaiClient.build
      end

      def preview(item)
        @previews.jpeg(Ai::PictureScout::Preview.new(item.image_url.hash.abs, self.class.thumb_url(item.image_url), nil))
      rescue Media::Error, Media::Ffmpeg::Error => e
        Rails.logger.warn("Media catalog could not preview #{item.image_url}: #{e.message}")
        nil
      end

      # id => the model's hash for that picture.
      def describe(topic, shown)
        content = [ { type: "text", text: "Topic: #{topic}" } ] + shown.flat_map do |id, item, jpeg|
          [ { type: "text", text: label(id, item) },
            { type: "image_url", image_url: { url: "data:image/jpeg;base64,#{Base64.strict_encode64(jpeg)}", detail: "low" } } ]
        end
        parameters = { model: model, messages: [ { role: "system", content: SYSTEM_PROMPT }, { role: "user", content: content } ] }
        parameters[:reasoning_effort] = "low" if model.start_with?("gpt-5", "o")
        response = client.chat(parameters: parameters)
        track(response.fetch("usage", {}))
        parse(response.dig("choices", 0, "message", "content"))
      end

      def label(id, item)
        title = CGI.unescape(item.page_url.to_s[/File:(.+)\z/, 1].to_s).tr("_", " ").sub(/\.\w+\z/, "")
        [ id, title.presence, (item.taken_on.presence && "taken #{item.taken_on}"), item.description.to_s.squish.first(100).presence ]
          .compact.join(" | ")
      end

      def parse(text)
        data = JSON.parse(text.to_s[/\{.*\}/m].to_s) rescue {}
        Array(data.is_a?(Hash) ? data["pictures"] : nil).select { |picture| picture.is_a?(Hash) }.index_by { |picture| picture["id"].to_s }
      end

      def entry(id, item, data)
        Entry.new(id: id, item: item, shows: data["shows"].to_s.squish.first(200),
                  people: Array(data["people"]).map { |name| name.to_s.squish }.compact_blank.first(5),
                  year: data["year"].to_s[/\d{4}/], kind: data["kind"].presence_in(KINDS) || "other",
                  usable: data["usable"] != false)
      end

      def track(usage)
        @usage[:input] += usage.fetch("prompt_tokens", 0)
        @usage[:output] += usage.fetch("completion_tokens", 0)
        @usage[:total] += usage.fetch("total_tokens", 0)
      end

      def cost
        prices = PRICING_PER_MILLION.fetch(model, { input: 0, output: 0 })
        ((@usage[:input] * prices[:input] + @usage[:output] * prices[:output]) / 1_000_000.0).to_d.round(6)
      end
  end
end
