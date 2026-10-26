# Splits narration into chunks no longer than `limit` characters, breaking only at
# sentence boundaries. A sentence longer than the limit is split at word boundaries.
class NarrationChunker
  SENTENCE_BOUNDARY = /(?<=[.!?])\s+/

  def initialize(text, limit:)
    @text = text.to_s.squish
    @limit = limit
  end

  def chunks
    result = []
    current = +""

    sentences.each do |sentence|
      if sentence.length > @limit
        result << current unless current.empty?
        current = +""
        result.concat(split_oversized(sentence))
        next
      end

      candidate = current.empty? ? sentence : "#{current} #{sentence}"
      if candidate.length > @limit
        result << current
        current = sentence.dup
      else
        current = candidate
      end
    end

    result << current unless current.empty?
    result
  end

  private
    def sentences
      @text.split(SENTENCE_BOUNDARY)
    end

    def split_oversized(sentence)
      pieces = []
      current = +""

      sentence.split(" ").each do |word|
        raise ArgumentError, "word longer than #{@limit} characters" if word.length > @limit

        candidate = current.empty? ? word : "#{current} #{word}"
        if candidate.length > @limit
          pieces << current
          current = word.dup
        else
          current = candidate
        end
      end

      pieces << current unless current.empty?
      pieces
    end
end
