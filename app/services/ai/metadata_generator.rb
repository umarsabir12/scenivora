module Ai
  # Writes the YouTube title, description, tags and category from the script, in one JSON call.
  class MetadataGenerator
    Result = Data.define(:title, :description, :tags, :category, :total_tokens, :cost_usd)

    CATEGORIES = [
      "Film & Animation", "Autos & Vehicles", "Music", "Pets & Animals", "Sports", "Travel & Events",
      "Gaming", "People & Blogs", "Comedy", "Entertainment", "News & Politics", "Howto & Style",
      "Education", "Science & Technology", "Nonprofits & Activism"
    ].freeze
    DEFAULT_CATEGORY = "Education".freeze
    MAX_TITLE = 100
    MAX_TAGS = 15
    MAX_TAG_LENGTH = 30
    MAX_TAGS_TOTAL = 450 # YouTube allows 500 characters of tags in total
    MAX_SCRIPT_CHARACTERS = 8_000

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You write YouTube metadata for a faceless documentary-style video. Input: the topic, tone and narration.

      Return a JSON object:
      {
        "title": "<under 70 characters, curiosity-driven, accurate, no clickbait lies, no ALL CAPS words>",
        "description": "<2 short paragraphs: a hook sentence, then what the video covers. No hashtags, no links, no credits>",
        "tags": ["<8 to 15 short search phrases>"],
        "category": "<one of: #{CATEGORIES.join(", ")}>"
      }
      Return only the JSON object.
    PROMPT

    def self.estimated_cost(script_text)
      model = ENV.fetch("OPENAI_TEXT_MODEL", Ai::TextGenerator::DEFAULT_MODEL)
      rates = Ai::TextGenerator::PRICING_PER_MILLION.fetch(model, { input: 0, output: 0 })
      input_tokens = SYSTEM_PROMPT.length / 4 + [ script_text.length, MAX_SCRIPT_CHARACTERS ].min / 4
      ((input_tokens * rates[:input] + 400 * rates[:output]) / 1_000_000).to_d.round(5)
    end

    def initialize(generator: Ai::TextGenerator.new)
      @generator = generator
    end

    def call(topic:, tone:, script:)
      result = @generator.call(system_prompt: SYSTEM_PROMPT, temperature: 0.7, json: true,
        user_prompt: "Topic: #{topic}\nTone: #{tone}\n\nNarration:\n#{script.to_s.first(MAX_SCRIPT_CHARACTERS)}")
      data = JSON.parse(result.text)
      raise Ai::Error, "Metadata response was not a JSON object" unless data.is_a?(Hash)

      Result.new(
        title: data["title"].to_s.squish.first(MAX_TITLE),
        description: data["description"].to_s.strip,
        tags: clean_tags(data["tags"]),
        category: CATEGORIES.include?(data["category"]) ? data["category"] : DEFAULT_CATEGORY,
        total_tokens: result.total_tokens,
        cost_usd: result.cost_usd
      )
    rescue JSON::ParserError
      raise Ai::Error, "Metadata response was not valid JSON"
    end

    private
      def clean_tags(tags)
        cleaned = Array(tags).map { |tag| tag.to_s.squish.delete("#,<>") }.reject(&:empty?)
                              .select { |tag| tag.length <= MAX_TAG_LENGTH }.uniq(&:downcase).first(MAX_TAGS)
        total = 0
        cleaned.take_while { |tag| (total += tag.length) <= MAX_TAGS_TOTAL }
      end
  end
end
