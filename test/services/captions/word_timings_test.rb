require "test_helper"

class Captions::WordTimingsTest < ActiveSupport::TestCase
  Track = Struct.new(:timings, :duration_ms)
  Script = Struct.new(:body)

  test "spreads each part's words across its measured span, longer words taking longer" do
    track = Track.new([ { "text" => "Hi there", "start_ms" => 0, "end_ms" => 1_000 },
                        { "text" => "Extraordinary", "start_ms" => 1_000, "end_ms" => 3_000 } ], 3_000)

    words = Captions::WordTimings.new(track, Script.new("ignored")).words

    assert_equal %w[Hi there Extraordinary], words.map(&:text)
    assert_equal [ 0, 333, 1_000 ], words.map(&:start_ms)
    assert_equal [ 333, 1_000, 3_000 ], words.map(&:end_ms)
    assert_not Captions::WordTimings.new(track, nil).approximate?
  end

  test "without part timings, spreads the script across the whole narration and says so" do
    timings = Captions::WordTimings.new(Track.new([], 4_000), Script.new("one two three"))

    assert timings.approximate?
    words = timings.words
    assert_equal 0, words.first.start_ms
    assert_equal 4_000, words.last.end_ms
  end
end
