module Media
  # Mood footage for scenes no real picture fits: a stormy sea, drifting clouds, a misty river. Picks
  # the clip whose mood the scene's words call for, keeps modern city footage out of historical
  # videos, and avoids repeating a clip within a video while others are left. The clips are a fixed,
  # hand-checked list (config/fillers.yml), so picking one costs nothing.
  class Fillers
    Clip = Data.define(:mood, :era, :title, :video_url, :poster_url, :page_url, :credit, :license, :duration_ms)

    # Words (first 5 letters) that call for each mood.
    MOODS = {
      "sea" => %w[sea seas ocean voyag sail saile saili sailo wave waves ship ships boat coast shore islan navy naval cross exile],
      "harbour" => %w[harbo port docks wharf pier quay],
      "mist" => %w[myste secre unkno legen myth rumou memor forgo whisp silen fog mist misty],
      "night_sky" => %w[night stars star sky heave dream unive fate desti midni dark darkn],
      "clouds" => %w[years decad time passe later chang futur seaso weath],
      "landscape" => %w[land journ trave road mount valle deser front homel count terri empir],
      "fire" => %w[war battl fire flame burn burne destr rage revol confl attac siege blaze explo],
      "rain" => %w[rain grief sorro mourn tears loss sad funer death died grave],
      "forest" => %w[fores natur peace quiet villa garde child home woods trees],
      "city" => %w[city crowd fame moder today world globa busin money succe milli]
    }.freeze
    # Without a telling word, one of these calm moods is used.
    NEUTRAL = %w[clouds mist landscape night_sky].freeze
    MODERN_BEFORE = 1960
    YEAR = /(?<!\d)(1[5-9]\d\d|20[0-3]\d)(?!\d)/

    def self.clips
      @clips ||= YAML.load_file(Rails.root.join("config/fillers.yml")).map { |row| Clip.new(**row.symbolize_keys) }
    end

    def self.filler?(url)
      @urls ||= clips.map(&:video_url).to_set
      @urls.include?(url)
    end

    # clips: the list to pick from (the configured one by default).
    def initialize(clips: self.class.clips)
      @clips = clips
    end

    # The best clip for a scene, as a VideoResult. used_urls: clips already in this video, picked
    # again only when every fitting clip is used. historical: no modern footage.
    def pick(text, used_urls: [], historical: false)
      words = text.to_s.downcase.scan(/[[:alpha:]]+/).map { |word| word.first(5) }.to_set
      allowed = @clips.reject { |clip| historical && clip.era == "modern" }
      return if allowed.empty?

      wanted = MOODS.select { |_, stems| stems.any? { |stem| words.include?(stem) } }
                    .max_by { |_, stems| stems.count { |stem| words.include?(stem) } }&.first
      moods = wanted ? [ wanted, *NEUTRAL ] : NEUTRAL
      fitting = allowed.select { |clip| moods.include?(clip.mood) }.sort_by { |clip| moods.index(clip.mood) }
      fitting = allowed if fitting.empty?
      clip = fitting.find { |candidate| !used_urls.include?(candidate.video_url) } ||
             allowed.find { |candidate| !used_urls.include?(candidate.video_url) } || fitting.first
      to_result(clip)
    end

    # Whether a video is about a time before modern footage would fit, from the years it names.
    def self.historical?(*texts)
      years = texts.join(" ").scan(YEAR).flatten.map(&:to_i)
      years.any? && years.min < MODERN_BEFORE
    end

    private
      def to_result(clip)
        VideoResult.new(provider: CommonsVideoSearch::PROVIDER, title: clip.title, video_url: clip.video_url,
                        poster_url: clip.poster_url, page_url: clip.page_url, credit: clip.credit, license: clip.license,
                        duration_ms: clip.duration_ms, description: "Filler: #{clip.mood.tr("_", " ")}")
      end
  end
end
