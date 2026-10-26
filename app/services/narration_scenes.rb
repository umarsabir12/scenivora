# Splits narration into scenes of about 10 seconds, timed from the real narration length.
#
# The number of scenes comes from the duration. Sentences are assigned by where they sit in
# the narration, so scenes always break on sentence boundaries. Each scene's time is its share
# of the words, scaled to the measured duration.
class NarrationScenes
  SECONDS_PER_SCENE = 10

  Scene = Data.define(:position, :text, :start_ms, :duration_ms, :search_query)

  def initialize(text, total_ms)
    @text = text.to_s.squish
    @total_ms = total_ms
  end

  def scenes
    sentences = @text.split(/(?<=[.!?])\s+/)
    words = sentences.map { |s| s.split.size }
    total_words = words.sum
    return [] if total_words.zero?

    count = [ (@total_ms / 1000.0 / SECONDS_PER_SCENE).round, 1 ].max
    words_per_scene = total_words.to_f / count

    groups = sentences.each_with_index.group_by do |_, index|
      middle = words.first(index).sum + words[index] / 2.0
      [ (middle / words_per_scene).floor, count - 1 ].min
    end

    build(groups.values.map { |pairs| pairs.map(&:first) }, groups.values.map { |pairs| pairs.sum { |_, i| words[i] } }, total_words)
  end

  private
    def build(texts, word_counts, total_words)
      start_ms = 0
      texts.each_with_index.map do |group, index|
        share = word_counts[index].to_f / total_words
        duration = index == texts.size - 1 ? @total_ms - start_ms : (share * @total_ms).round
        text = group.join(" ")
        scene = Scene.new(position: index + 1, text: text, start_ms: start_ms, duration_ms: duration,
                          search_query: ::Scene.query_for(text))
        start_ms += duration
        scene
      end
    end
end
