require "test_helper"

class Media::FfmpegTest < ActiveSupport::TestCase
  test "raises a clear install hint when ffmpeg is not on the PATH" do
    original_path = ENV["PATH"]
    original_bins = ENV.values_at("FFMPEG_BIN", "FFPROBE_BIN")
    ENV["PATH"] = ""
    ENV["FFMPEG_BIN"] = ENV["FFPROBE_BIN"] = "/nonexistent/ffmpeg"

    error = assert_raises(Media::Ffmpeg::Error) do
      Media::Ffmpeg.new.duration_ms("/tmp/does-not-matter.mp3")
    end

    assert_match "brew install ffmpeg", error.message
  ensure
    ENV["PATH"] = original_path
    ENV["FFMPEG_BIN"], ENV["FFPROBE_BIN"] = original_bins
  end

  test "a long scene is cut into shots of 3 to 5 seconds that add up to its frames" do
    assert_equal [ 138, 138 ], Media::Ffmpeg.shot_frames(276, 30), "9.2 s: two shots"
    assert_equal [ 108, 108, 108 ], Media::Ffmpeg.shot_frames(324, 30), "10.8 s: three, not two of 5.4 s"
    assert_equal [ 150 ], Media::Ffmpeg.shot_frames(150, 30), "5 s: one shot"
    assert_equal [ 177 ], Media::Ffmpeg.shot_frames(177, 30), "5.9 s: two shots would be under 3 s"
    assert_equal [ 60 ], Media::Ffmpeg.shot_frames(60, 30)

    [ 181, 299, 451, 1000 ].each do |frames|
      shots = Media::Ffmpeg.shot_frames(frames, 30)
      assert_equal frames, shots.sum
      assert shots.all? { |shot| shot.between?(90, 150) }, "#{frames} frames: #{shots.inspect}"
    end
  end
end
