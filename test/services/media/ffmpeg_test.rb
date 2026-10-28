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
end
