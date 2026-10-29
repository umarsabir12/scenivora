# Lays a script out as storyboard scenes: one per paragraph, since the script is written one shot
# per paragraph. A paragraph much longer than a shot is split at sentences. Until the voice exists,
# each scene's time is estimated from its words; the voice later replaces it with the measured time.
class StoryboardScenes
  PARAGRAPH_BREAK = /\n\s*\n/
  SENTENCE_BOUNDARY = /(?<=[.!?])\s+/
  MAX_WORDS = 45
  WORDS_PER_PIECE = 30
  MIN_DURATION_MS = 2_000

  Scene = Data.define(:position, :text, :start_ms, :duration_ms)

  def initialize(text, words_per_minute: Project::WORDS_PER_MINUTE)
    @text = text.to_s
    @words_per_minute = words_per_minute
  end

  def scenes
    texts = @text.split(PARAGRAPH_BREAK).map(&:squish).reject(&:empty?).flat_map { |paragraph| pieces(paragraph) }
    start_ms = 0
    texts.each_with_index.map do |text, index|
      duration = estimated_ms(text)
      scene = Scene.new(position: index + 1, text: text, start_ms: start_ms, duration_ms: duration)
      start_ms += duration
      scene
    end
  end

  # Joins scene texts back into a script, one paragraph per scene.
  def self.script_for(texts)
    texts.map(&:squish).reject(&:empty?).join("\n\n")
  end

  private
    def pieces(paragraph)
      return [ paragraph ] if paragraph.split.size <= MAX_WORDS

      paragraph.split(SENTENCE_BOUNDARY).each_with_object([ +"" ]) do |sentence, groups|
        groups << +"" if groups.last.split.size + sentence.split.size > WORDS_PER_PIECE && groups.last.present?
        groups.last << " " if groups.last.present?
        groups.last << sentence
      end
    end

    def estimated_ms(text)
      [ (text.split.size * 60_000.0 / @words_per_minute).round, MIN_DURATION_MS ].max
    end
end
