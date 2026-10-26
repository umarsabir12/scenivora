require "test_helper"

class Media::FfmpegTest < ActiveSupport::TestCase
  test "raises a clear install hint when ffmpeg is not on the PATH" do
    original_path = ENV["PATH"]
    ENV["PATH"] = ""

    error = assert_raises(Media::Ffmpeg::Error) do
      Media::Ffmpeg.new.duration_ms("/tmp/does-not-matter.mp3")
    end

    assert_match "brew install ffmpeg", error.message
  ensure
    ENV["PATH"] = original_path
  end
end
