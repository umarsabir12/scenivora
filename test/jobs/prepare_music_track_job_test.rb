require "test_helper"

class PrepareMusicTrackJobTest < ActiveJob::TestCase
  class FakeFfmpeg
    def initialize(error: nil)
      @error = error
    end

    def duration_ms(_path)
      raise @error if @error

      95_000
    end
  end

  setup do
    @project = project_with_approved_scenes
  end

  test "downloads a Commons track, attaches it and measures its length" do
    track = @project.create_music_track!(title: "Home Song", credit: "Ross", license: "CC BY 4.0",
                                         source_url: "https://upload.wikimedia.org/x/Home_Song.mp3")
    downloader = ->(_url, path, max_bytes:) { File.binwrite(path, File.binread(Rails.root.join("test/fixtures/files/tone.mp3"))); path }

    with_stubbed_method(Media::Download, :to_file, downloader) do
      with_stubbed_new(Media::Ffmpeg, FakeFfmpeg.new) { PrepareMusicTrackJob.perform_now(track) }
    end

    track.reload
    assert track.ready?
    assert track.file.attached?
    assert_equal "home-song.mp3", track.file.filename.to_s
    assert_equal 95_000, track.duration_ms
  end

  test "measures an uploaded track" do
    track = @project.build_music_track(title: "Mine", credit: "Your upload", license: "Provided by you")
    track.file.attach(io: File.open(Rails.root.join("test/fixtures/files/tone.mp3")), filename: "mine.mp3", content_type: "audio/mpeg")
    track.save!

    with_stubbed_new(Media::Ffmpeg, FakeFfmpeg.new) { PrepareMusicTrackJob.perform_now(track) }

    assert track.reload.ready?
    assert_equal 95_000, track.duration_ms
  end

  test "a failed download marks the track failed with the reason" do
    track = @project.create_music_track!(title: "Gone", source_url: "https://upload.wikimedia.org/x/gone.ogg")
    failing = ->(*_args, **_kwargs) { raise Media::Error, "upload.wikimedia.org responded with 404" }

    with_stubbed_method(Media::Download, :to_file, failing) { PrepareMusicTrackJob.perform_now(track) }

    track.reload
    assert track.failed?
    assert_equal "upload.wikimedia.org responded with 404", track.error
  end
end
