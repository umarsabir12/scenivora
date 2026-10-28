require "test_helper"

class NarrationPartsTest < ActiveSupport::TestCase
  test "makes one part per paragraph" do
    text = "First paragraph. Still first.\n\nSecond paragraph.\n \n\nThird."

    assert_equal [ "First paragraph. Still first.", "Second paragraph.", "Third." ], NarrationParts.new(text, limit: 4096).parts
  end

  test "splits a paragraph longer than the limit at sentence boundaries" do
    paragraph = Array.new(10) { |i| "Sentence #{i} is here." }.join(" ")

    parts = NarrationParts.new("Intro.\n\n#{paragraph}", limit: 60).parts

    assert_equal "Intro.", parts.first
    assert parts.size > 2
    assert parts.all? { |part| part.length <= 60 }
    assert_equal paragraph, parts.drop(1).join(" ")
  end
end
