require "test_helper"

class Captions::AssBuilderTest < ActiveSupport::TestCase
  Word = Captions::WordTimings::Word

  def words(text, ms_each: 400)
    text.split.each_with_index.map { |word, i| Word.new(text: word, start_ms: i * ms_each, end_ms: (i + 1) * ms_each) }
  end

  def dialogues(ass, style = "Caption")
    ass.lines.grep(/\ADialogue: \d,[^,]+,[^,]+,#{style},/).map(&:chomp)
  end

  test "writes a 1080p ASS file using the bundled font" do
    ass = Captions::AssBuilder.new(words("Hello there.")).to_s

    assert_includes ass, "PlayResX: 1920"
    assert_includes ass, "PlayResY: 1080"
    assert_includes ass, "Style: Caption,Anton,"
  end

  test "shows 1 to 3 upper-case words at a time, breaking after punctuation" do
    lines = dialogues(Captions::AssBuilder.new(words("the sea rises twice, then falls again")).to_s)

    texts = lines.map { |line| line.split(",,0,0,0,,").last }
    assert_equal [ "THE SEA RISES", "TWICE,", "THEN FALLS AGAIN" ], texts
  end

  test "highlights numbers and names in yellow, but not a capital that starts a sentence" do
    text = dialogues(Captions::AssBuilder.new(words("In 1856 Tesla moved.")).to_s).map { |line| line.split(",,0,0,0,,").last }.join(" ")

    assert_includes text, "{\\c&H0AD6FF&}1856{\\c&HFFFFFF&}"
    assert_includes text, "{\\c&H0AD6FF&}TESLA{\\c&HFFFFFF&}"
    assert_not_includes text, "{\\c&H0AD6FF&}IN"
  end

  test "uses ASS timestamps and holds a caption until the next one when they are close" do
    lines = dialogues(Captions::AssBuilder.new(words("one two three four", ms_each: 500)).to_s)

    assert_equal "Dialogue: 0,0:00:00.00,0:00:01.50,Caption,,0,0,0,,ONE TWO THREE", lines.first
    assert_equal "Dialogue: 0,0:00:01.50,0:00:02.25,Caption,,0,0,0,,FOUR", lines.last
  end

  test "adds the hook title over the first seconds" do
    ass = Captions::AssBuilder.new(words("Hi."), hook: "Why the Sea Rises Twice Every Single Day").to_s

    hook = dialogues(ass, "Hook").first
    assert hook.start_with?("Dialogue: 1,0:00:00.00,0:00:02.80,Hook,")
    assert_includes hook, "WHY THE SEA RISES TWICE\\N{\\c&H0AD6FF&}EVERY SINGLE DAY"
  end

  test "strips ASS markup characters from the text" do
    text = dialogues(Captions::AssBuilder.new(words("a {b} c\\d")).to_s).first

    assert_includes text, "A (B) CD"
  end
end
