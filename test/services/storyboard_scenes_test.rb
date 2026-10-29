require "test_helper"

class StoryboardScenesTest < ActiveSupport::TestCase
  test "one scene per paragraph, timed from its words at 150 a minute" do
    text = "#{"word " * 25}\n\n#{"word " * 15}\n\n\n#{"word " * 30}"

    scenes = StoryboardScenes.new(text).scenes

    assert_equal [ 1, 2, 3 ], scenes.map(&:position)
    assert_equal [ 10_000, 6_000, 12_000 ], scenes.map(&:duration_ms)
    assert_equal [ 0, 10_000, 16_000 ], scenes.map(&:start_ms)
  end

  test "a paragraph much longer than a shot is split at sentences" do
    short = "#{"word " * 9}end."
    long = "#{"word " * 19}end."
    scenes = StoryboardScenes.new([ short, short, long, short ].join(" ")).scenes

    assert_equal [ 20, 30 ], scenes.map { |scene| scene.text.split.size }
  end

  test "a very short paragraph still gets a couple of seconds" do
    assert_equal StoryboardScenes::MIN_DURATION_MS, StoryboardScenes.new("Calypso.").scenes.first.duration_ms
  end

  test "joins scene texts back into a script, one paragraph each" do
    assert_equal "First shot.\n\nSecond shot.", StoryboardScenes.script_for([ " First  shot. ", "", "Second shot." ])
  end
end
