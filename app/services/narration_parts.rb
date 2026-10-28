# Splits narration into voice parts: one per paragraph. A paragraph longer than the speech limit is
# split further at sentence boundaries. Measuring each part gives each paragraph's exact timing.
class NarrationParts
  PARAGRAPH_BREAK = /\n\s*\n/

  def initialize(text, limit:)
    @text = text.to_s
    @limit = limit
  end

  def parts
    @text.split(PARAGRAPH_BREAK).map(&:strip).reject(&:empty?)
         .flat_map { |paragraph| NarrationChunker.new(paragraph, limit: @limit).chunks }
  end
end
