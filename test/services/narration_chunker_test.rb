require "test_helper"

class NarrationChunkerTest < ActiveSupport::TestCase
  LIMIT = 4096

  test "keeps short text in a single chunk" do
    chunks = NarrationChunker.new("A short script. It fits.", limit: LIMIT).chunks

    assert_equal [ "A short script. It fits." ], chunks
  end

  test "splits long text into chunks under the limit, at sentence boundaries" do
    sentences = Array.new(400) { |i| "This is sentence number #{i} about the topic." }
    text = sentences.join(" ")

    chunks = NarrationChunker.new(text, limit: LIMIT).chunks

    assert chunks.size > 1
    assert chunks.all? { |chunk| chunk.length <= LIMIT }
    assert chunks.all? { |chunk| chunk.end_with?(".") }, "every chunk should end on a full sentence"
    assert_equal sentences, chunks.join(" ").split(/(?<=\.) /)
  end

  test "loses no words when splitting" do
    text = Array.new(300) { |i| "Word#{i} is here, and it matters." }.join(" ")

    chunks = NarrationChunker.new(text, limit: 500).chunks

    assert_equal text.split, chunks.join(" ").split
  end

  test "splits a single sentence longer than the limit at word boundaries" do
    sentence = ([ "word" ] * 50).join(" ")

    chunks = NarrationChunker.new(sentence, limit: 40).chunks

    assert chunks.size > 1
    assert chunks.all? { |chunk| chunk.length <= 40 }
    assert_equal sentence, chunks.join(" ")
  end

  test "raises when a single word exceeds the limit" do
    error = assert_raises(ArgumentError) do
      NarrationChunker.new("x" * 20, limit: 10).chunks
    end

    assert_match "word longer than 10 characters", error.message
  end

  test "returns no chunks for blank text" do
    assert_equal [], NarrationChunker.new("   \n  ", limit: LIMIT).chunks
  end
end
