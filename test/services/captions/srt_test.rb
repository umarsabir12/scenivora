require "test_helper"

class Captions::SrtTest < ActiveSupport::TestCase
  Word = Captions::WordTimings::Word

  def words(text, ms_each: 400)
    text.split.each_with_index.map { |word, i| Word.new(text: word, start_ms: i * ms_each, end_ms: (i + 1) * ms_each) }
  end

  test "writes numbered cues with SRT timestamps, breaking at sentence ends" do
    srt = Captions::Srt.new(words("Tides rise. The moon pulls them.")).to_s

    assert_equal <<~SRT, srt
      1
      00:00:00,000 --> 00:00:00,800
      Tides rise.

      2
      00:00:00,800 --> 00:00:02,400
      The moon pulls them.
    SRT
  end

  test "keeps every cue to one readable line" do
    srt = Captions::Srt.new(words("word " * 40)).to_s
    lines = srt.lines.map(&:chomp).reject { |line| line.empty? || line.match?(/\A\d+\z/) || line.include?("-->") }

    assert lines.all? { |line| line.length <= Captions::Srt::MAX_CHARS }
    assert_equal 40, lines.join(" ").split.size
  end

  test "very short cues are stretched, but never past the next cue" do
    srt = Captions::Srt.new(words("Yes. No.", ms_each: 200)).to_s

    assert_includes srt, "00:00:00,000 --> 00:00:00,200"
    assert_includes srt, "00:00:00,200 --> 00:00:00,900"
  end

  test "formats hours" do
    srt = Captions::Srt.new([ Word.new(text: "Late.", start_ms: 3_723_456, end_ms: 3_724_456) ]).to_s

    assert_includes srt, "01:02:03,456 --> 01:02:04,456"
  end

  test "a sentence's last word is not left on its own" do
    srt = Captions::Srt.new(words("Nikola Tesla was a genius who changed the world.")).to_s

    assert_includes srt, "\nNikola Tesla was a genius who changed the world.\n"
    assert_equal 1, srt.scan("-->").size
  end
end
