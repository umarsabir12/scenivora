module Captions
  # Writes burned-in captions as an ASS subtitle file for ffmpeg's `subtitles` filter: large bold
  # words, 1 to 3 at a time, with numbers and names in yellow, and an optional hook title over the
  # first seconds.
  class AssBuilder
    MAX_WORDS = 3
    MAX_CHARS = 16
    MIN_CAPTION_MS = 300
    LINGER_MS = 250
    JOIN_GAP_MS = 600 # if the next caption starts this soon, hold this one until then
    HOOK_MS = 2_800
    FONT = "Anton".freeze
    # ASS colours are &HBBGGRR&.
    YELLOW = "&H0AD6FF&".freeze # RGB(255, 214, 10)
    WHITE = "&HFFFFFF&".freeze

    # words: objects with text, start_ms and end_ms (see Captions::WordTimings).
    def initialize(words, hook: nil, width: 1920, height: 1080)
      @words = words
      @hook = hook
      @width = width
      @height = height
    end

    def write(path)
      File.write(path, to_s)
      path
    end

    def to_s
      header + hook_event + caption_events.join
    end

    private
      def header
        <<~ASS
          [Script Info]
          ScriptType: v4.00+
          PlayResX: #{@width}
          PlayResY: #{@height}
          WrapStyle: 2
          ScaledBorderAndShadow: yes

          [V4+ Styles]
          Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
          Style: Caption,#{FONT},88,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,1,0,1,6,2,2,80,80,120,1
          Style: Hook,#{FONT},110,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,1,0,1,8,3,8,100,100,90,1

          [Events]
          Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        ASS
      end

      # The hook title: top of the frame, last line in yellow, fading out.
      def hook_event
        return "" if @hook.blank?

        lines = wrap(clean(@hook).upcase, 24)
        lines[-1] = "{\\c#{YELLOW}}#{lines[-1]}" if lines.size > 1
        "Dialogue: 1,#{timestamp(0)},#{timestamp(HOOK_MS)},Hook,,0,0,0,,{\\fad(0,400)}#{lines.join("\\N")}\n"
      end

      def caption_events
        groups = chunks
        groups.each_with_index.map do |group, index|
          start_ms = group.first.start_ms
          next_start = groups[index + 1]&.first&.start_ms
          end_ms = next_start && next_start - group.last.end_ms < JOIN_GAP_MS ? next_start : group.last.end_ms + LINGER_MS
          end_ms = [ end_ms, start_ms + MIN_CAPTION_MS ].max
          "Dialogue: 0,#{timestamp(start_ms)},#{timestamp(end_ms)},Caption,,0,0,0,,#{styled(group)}\n"
        end
      end

      # 1 to 3 words, at most 16 characters, always breaking after punctuation.
      def chunks
        groups = []
        current = []
        @words.each do |word|
          line = (current + [ word ]).map(&:text).join(" ")
          if current.any? && (current.size >= MAX_WORDS || line.length > MAX_CHARS || current.last.text.match?(/[.,!?;:]["')]?\z/))
            groups << current
            current = []
          end
          current << word
        end
        groups << current if current.any?
        groups
      end

      def styled(group)
        group.map do |word|
          text = clean(word.text).upcase
          highlight?(word) ? "{\\c#{YELLOW}}#{text}{\\c#{WHITE}}" : text
        end.join(" ")
      end

      # Numbers, and capitalised words that don't start a sentence (usually names and places).
      def highlight?(word)
        return true if word.text.match?(/\d/)
        return false unless word.text.match?(/\A["'(]?[A-Z]/)

        index = @words.index(word)
        index&.positive? && !@words[index - 1].text.match?(/[.!?]["')]?\z/)
      end

      # Braces and backslashes are ASS markup, so they can't appear in caption text.
      def clean(text)
        text.to_s.tr("{}", "()").delete("\\")
      end

      def wrap(text, width)
        text.split.each_with_object([ "" ]) do |word, lines|
          if lines.last.empty? || "#{lines.last} #{word}".length <= width
            lines[-1] = "#{lines.last} #{word}".strip
          else
            lines << word
          end
        end
      end

      def timestamp(ms)
        hours, rest = ms.divmod(3_600_000)
        minutes, rest = rest.divmod(60_000)
        format("%d:%02d:%05.2f", hours, minutes, rest / 1000.0)
      end
  end
end
