module Ai
  # A small search agent for one scene the search left without a picture. It searches the way a
  # person would: short archive-style queries, the pictures of the articles about the scene's
  # subject, a look at the most promising results, and a new search when they are wrong. It may
  # only choose a picture it has looked at, from what its own searches returned, so it can't invent
  # a file. Its choice still goes through the picture check like any other candidate.
  class PictureScout
    # choice: the chosen Media::ImageResult, or nil.
    Result = Data.define(:choice, :reason, :total_tokens, :cost_usd)

    PROVIDER = "openai".freeze
    DEFAULT_MODEL = "gpt-5-mini".freeze
    # USD per one million tokens. Keep in sync with the provider's price list.
    PRICING_PER_MILLION = {
      "gpt-5-mini" => { input: 0.25, output: 2.00 },
      "gpt-4o-mini" => { input: 0.15, output: 0.60 }
    }.freeze
    # Model calls per scene; the last one must answer.
    MAX_TURNS = 6
    MAX_LOOK = 6
    RESULTS_SHOWN = 8
    SEARCH_LIMIT = 10

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You find one real, freely licensed picture for a scene of a documentary video. The automatic
      search found nothing that fits. Search like an archivist:
      - search_commons with short queries of 2-4 words: the name of the event, place, ship, building
        or person, plus at most a year or one telling word ("Molasses Flood 1919", "USS Nantucket").
        Every word must match, so a long query finds nothing. When a search finds nothing useful, try
        a different name or a broader one rather than adding words.
      - article_pictures for an English Wikipedia article about the scene's subject: its pictures and
        its Commons category, chosen by editors for exactly that subject.
      - look at the most promising results (up to 6 at a time) before choosing. You may only choose a
        picture you have looked at.
      Choose a picture a viewer would recognise as the moment narrated: the right subject, place and
      era. When no picture of the exact moment can exist, a real picture of the same event, place or
      people from that time is right. Reject modern photos for historical moments, other people's
      stories, pictures that are mostly text unless the scene is about that document, watermarks,
      and anything graphic. Follow the scene's depiction rule. If nothing fits, choose none.

      When you are done, answer only with JSON:
      {"choice": "<the id of the picture>" | null, "reason": "<one short sentence>"}
    PROMPT

    DEPICTION_RULES = {
      "normal" => "Normal.",
      "no_face" => "A revered religious figure: never a picture that shows this person's face, in any medium.",
      "no_figure" => "A prophet: never a picture that depicts this person in any form."
    }.freeze

    TOOLS = [
      { type: "function", function: {
        name: "search_commons", description: "Search Wikimedia Commons for freely licensed photos.",
        parameters: { type: "object", properties: { query: { type: "string", description: "2-4 words" } }, required: [ "query" ] } } },
      { type: "function", function: {
        name: "article_pictures", description: "The pictures of an English Wikipedia article and of its Commons category.",
        parameters: { type: "object", properties: { article: { type: "string", description: "The exact article title" } },
                      required: [ "article" ] } } },
      { type: "function", function: {
        name: "look", description: "See small previews of up to 6 pictures found so far.",
        parameters: { type: "object", properties: { ids: { type: "array", items: { type: "string" } } }, required: [ "ids" ] } } }
    ].freeze

    # What PreviewFetcher needs to fetch a found picture's preview.
    Preview = Struct.new(:id, :image_url, :poster_url) do
      def video? = false
      def stored_file? = false
    end

    # articles: answers images(article) with ImageResults, like the search job's cached library fetcher.
    def initialize(articles:, search: Media::CommonsSearch.new, previews: Media::PreviewFetcher.new,
                   model: ENV.fetch("OPENAI_SCOUT_MODEL", DEFAULT_MODEL), client: nil)
      @articles = articles
      @search = search
      @previews = previews
      @model = model
      @client = client
    end

    # scene: a Scene with text, plan and depiction. used_urls: pictures other scenes already show.
    def call(scene:, used_urls: [])
      @found = {}
      @looked = Set.new
      @used = used_urls.to_set
      @usage = { input: 0, output: 0, total: 0 }
      messages = [ { role: "system", content: SYSTEM_PROMPT }, { role: "user", content: brief(scene) } ]

      MAX_TURNS.times do |turn|
        message = ask(messages, last: turn == MAX_TURNS - 1)
        calls = Array(message["tool_calls"])
        # Only what a request may carry back: the answer also holds fields such as annotations.
        messages << { role: "assistant", content: message["content"], tool_calls: (calls if calls.any?) }.compact
        return answer(message["content"]) if calls.empty?

        images = calls.flat_map { |call| run_tool(call, messages) }
        messages << pictures_message(images) if images.any?
      end
      answer(nil)
    rescue OpenAI::Error, Faraday::Error => e
      raise Ai::Error.from(e, "Picture scout failed")
    end

    private
      attr_reader :model

      def client
        @client ||= Ai::OpenaiClient.build
      end

      def brief(scene)
        articles = Array(scene.plan["articles"]) + Array(scene.project.settings["articles"])
        [ "Topic: #{scene.project.prompt}", "Narration: #{scene.text}",
          "Should show: #{scene.plan["visual_intent"].presence || scene.text}",
          "Depiction rule: #{DEPICTION_RULES.fetch(scene.depiction)}",
          ("Articles about this video: #{articles.uniq.join("; ")}" if articles.any?),
          "Queries that already failed: #{Array(scene.plan["search_queries"]).join("; ")}" ].compact.join("\n")
      end

      def ask(messages, last:)
        parameters = { model: model, messages: messages, tools: TOOLS }
        parameters[:tool_choice] = "none" if last
        parameters[:reasoning_effort] = "low" if model.start_with?("gpt-5", "o")
        response = client.chat(parameters: parameters)
        usage = response.fetch("usage", {})
        @usage[:input] += usage.fetch("prompt_tokens", 0)
        @usage[:output] += usage.fetch("completion_tokens", 0)
        @usage[:total] += usage.fetch("total_tokens", 0)
        response.dig("choices", 0, "message") || raise(Ai::Error, "Picture scout got no answer")
      end

      # Answers one tool call with a tool message. Returns the [id, jpeg] previews a look produced.
      def run_tool(call, messages)
        arguments = JSON.parse(call.dig("function", "arguments").to_s) rescue {}
        images = []
        content =
          case call.dig("function", "name")
          when "search_commons" then listing(@search.search(arguments["query"].to_s.squish, limit: SEARCH_LIMIT))
          when "article_pictures" then listing(@articles.images(arguments["article"].to_s.squish))
          when "look"
            images = previews(Array(arguments["ids"]).map(&:to_s).first(MAX_LOOK))
            images.any? ? "The previews follow, labelled by id: #{images.map(&:first).join(", ")}." : "None of those could be shown."
          else "Unknown tool."
          end
        messages << { role: "tool", tool_call_id: call["id"], content: content }
        images
      rescue Media::Error => e
        messages << { role: "tool", tool_call_id: call["id"], content: "That search failed (#{e.message}). Try another." }
        []
      end

      # Registers new results under short ids and lists them for the model.
      def listing(results)
        fresh = results.reject { |result| @used.include?(result.image_url) }.first(RESULTS_SHOWN)
        return "Nothing found (pictures other scenes already show are left out)." if fresh.empty?

        fresh.map do |result|
          id = @found.key(result) || "p#{@found.size + 1}".tap { |key| @found[key] = result }
          [ "#{id}: #{title(result)}", (result.taken_on.presence && "taken #{result.taken_on}"),
            (result.source_article.presence && "article: #{result.source_article}"),
            result.description.to_s.first(120).presence ].compact.join(" | ")
        end.join("\n")
      end

      def title(result)
        CGI.unescape(result.page_url.to_s[/File:(.+)\z/, 1].to_s).tr("_", " ").sub(/\.\w+\z/, "").presence || result.image_url
      end

      def previews(ids)
        ids.filter_map do |id|
          result = @found[id]
          next unless result

          jpeg = @previews.jpeg(Preview.new(id, result.image_url, nil))
          next unless jpeg

          @looked << id
          [ id, jpeg ]
        rescue Media::Error, Media::Ffmpeg::Error => e
          Rails.logger.warn("Picture scout could not preview #{result.image_url}: #{e.message}")
          nil
        end
      end

      # Tool messages carry text only, so the previews come in a user message after them.
      def pictures_message(images)
        content = images.flat_map do |id, jpeg|
          [ { type: "text", text: id },
            { type: "image_url", image_url: { url: "data:image/jpeg;base64,#{Base64.strict_encode64(jpeg)}", detail: "low" } } ]
        end
        { role: "user", content: content }
      end

      # Only a picture the scout found and looked at counts as a choice.
      def answer(text)
        data = JSON.parse(text.to_s[/\{.*\}/m].to_s) rescue {}
        id = data["choice"].to_s if data.is_a?(Hash)
        choice = @found[id] if id && @looked.include?(id)
        reason = data.is_a?(Hash) ? data["reason"].to_s.squish.first(300) : ""
        Result.new(choice: choice, reason: reason, total_tokens: @usage[:total], cost_usd: cost)
      end

      def cost
        prices = PRICING_PER_MILLION.fetch(model) do
          Rails.logger.warn("No pricing configured for #{model}; recording $0 cost")
          { input: 0, output: 0 }
        end
        ((@usage[:input] * prices[:input] + @usage[:output] * prices[:output]) / 1_000_000.0).to_d.round(6)
      end
  end
end
