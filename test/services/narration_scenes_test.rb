require "test_helper"

class NarrationScenesTest < ActiveSupport::TestCase
  def narration(count)
    Array.new(count) { |i| "Sentence number #{i} keeps the story moving along nicely." }.join(" ")
  end

  test "scenes cover the narration exactly, end to end" do
    scenes = NarrationScenes.new(narration(40), 95_123).scenes

    assert_equal 0, scenes.first.start_ms
    scenes.each_cons(2) { |a, b| assert_equal a.start_ms + a.duration_ms, b.start_ms }
    assert_equal 95_123, scenes.last.start_ms + scenes.last.duration_ms
    assert_equal (1..scenes.size).to_a, scenes.map(&:position)
  end

  test "aims for about 10 seconds per scene" do
    scenes = NarrationScenes.new(narration(80), 120_000).scenes

    assert_equal 12, scenes.size
    scenes[0..-2].each { |scene| assert_includes 8_000..12_000, scene.duration_ms }
  end

  test "breaks only on sentence boundaries and keeps every word" do
    text = narration(30)

    scenes = NarrationScenes.new(text, 60_000).scenes

    assert_equal text.split, scenes.map(&:text).join(" ").split
    scenes.each { |scene| assert_match(/[.!?]\z/, scene.text) }
  end

  test "a short narration becomes one scene" do
    scenes = NarrationScenes.new("Only one short sentence.", 4_000).scenes

    assert_equal 1, scenes.size
    assert_equal 4_000, scenes.first.duration_ms
  end

  test "empty narration produces no scenes" do
    assert_equal [], NarrationScenes.new("   ", 10_000).scenes
  end

  test "search queries favour names and skip common words" do
    query = Scene.query_for("He said that Nikola Tesla was born in Croatia during 1856.")

    assert_includes query, "Nikola"
    assert_includes query, "Tesla"
    assert_not_includes query.split, "He"
    assert_not_includes query.split, "that"
  end
end
