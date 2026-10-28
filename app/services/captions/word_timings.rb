module Captions
  # Estimates when each narrated word is spoken. Each part's measured span is shared among its
  # words by length, so timing is exact at part (paragraph) boundaries and close in between.
  #
  # Voice tracks made before part timings existed have none; their words are spread across the
  # whole narration instead, which is approximate.
  class WordTimings
    Word = Data.define(:text, :start_ms, :end_ms)

    def initialize(track, script)
      @track = track
      @script = script
    end

    def approximate?
      @track.timings.blank?
    end

    def words
      parts.flat_map { |part| spread(part["text"].to_s.split, part["start_ms"].to_i, part["end_ms"].to_i) }
    end

    private
      def parts
        return @track.timings if @track.timings.present?

        [ { "text" => @script&.body.to_s, "start_ms" => 0, "end_ms" => @track.duration_ms.to_i } ]
      end

      # One extra unit per word stands in for the gap between words.
      def spread(words, start_ms, end_ms)
        weights = words.map { |word| word.length + 1 }
        total = weights.sum.to_f
        elapsed = 0

        words.zip(weights).map do |word, weight|
          word_start = start_ms + ((end_ms - start_ms) * elapsed / total).round
          elapsed += weight
          Word.new(text: word, start_ms: word_start, end_ms: start_ms + ((end_ms - start_ms) * elapsed / total).round)
        end
      end
  end
end
