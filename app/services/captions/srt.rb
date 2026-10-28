module Captions
  # Builds an SRT caption file for uploading to YouTube as a caption track. Cues are one readable
  # line each, ending at sentence or clause breaks where possible.
  class Srt
    MAX_CHARS = 42
    # A line may run this much over when the extra word ends the sentence, so it isn't left alone.
    SENTENCE_END_SLACK = 8
    MIN_CLAUSE_CHARS = 20
    MIN_CUE_MS = 700

    def initialize(words)
      @words = words
    end

    def to_s
      cues = group(@words)
      cues.each_with_index.map do |cue, index|
        next_start = cues[index + 1]&.first&.start_ms
        start_ms = cue.first.start_ms
        end_ms = [ cue.last.end_ms, start_ms + MIN_CUE_MS ].max
        end_ms = [ end_ms, next_start ].min if next_start

        "#{index + 1}\n#{timestamp(start_ms)} --> #{timestamp(end_ms)}\n#{cue.map(&:text).join(" ")}\n"
      end.join("\n")
    end

    private
      def group(words)
        cues = []
        current = []

        words.each do |word|
          if current.any? && too_long?(current + [ word ], word)
            cues << current
            current = []
          end
          current << word

          if cue_break?(word, current)
            cues << current
            current = []
          end
        end
        cues << current if current.any?
        cues
      end

      def too_long?(words, last_word)
        length = words.map(&:text).join(" ").length
        limit = sentence_end?(last_word) ? MAX_CHARS + SENTENCE_END_SLACK : MAX_CHARS
        length > limit
      end

      def sentence_end?(word)
        word.text.match?(/[.!?]["')\]]?\z/)
      end

      # A sentence end always closes a cue; a comma or colon does once the line is long enough.
      def cue_break?(word, current)
        sentence_end?(word) ||
          (word.text.match?(/[,;:]\z/) && current.map(&:text).join(" ").length >= MIN_CLAUSE_CHARS)
      end

      def timestamp(ms)
        hours, rest = ms.divmod(3_600_000)
        minutes, rest = rest.divmod(60_000)
        seconds, millis = rest.divmod(1_000)
        format("%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
      end
  end
end
