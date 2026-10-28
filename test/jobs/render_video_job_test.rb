require "test_helper"

class RenderVideoJobTest < ActiveJob::TestCase
  # Records each call and writes small placeholder files, so no ffmpeg is needed.
  class FakeFfmpeg
    attr_reader :clips, :finish_args, :captions

    def initialize(error: nil, captions: true)
      @error = error
      @clips = []
      @supports_captions = captions
    end

    def supports_captions?
      @supports_captions
    end

    def still_clip(image_path, frames, output_path, fps:, zoom_in:)
      raise @error if @error

      @clips << { image: File.binread(image_path), frames: frames, fps: fps, zoom_in: zoom_in }
      File.binwrite(output_path, "clip")
      output_path
    end

    def video_clip(source, start_ms, frames, output_path, fps:)
      raise @error if @error

      @clips << { video: source, start_ms: start_ms, frames: frames, fps: fps }
      File.binwrite(output_path, "clip")
      output_path
    end

    def concat(paths, output_path)
      File.binwrite(output_path, paths.map { |path| File.binread(path) }.join)
      output_path
    end

    def finish(**args)
      @finish_args = args
      @captions = File.read(args[:captions_path]) if args[:captions_path]
      File.binwrite(args[:output_path], "final mp4")
      args[:output_path]
    end

    def thumbnail(_video, output_path)
      File.binwrite(output_path, "jpg")
      output_path
    end
  end

  setup do
    @project = project_with_approved_scenes(status: "rendering")
    # A local, not an ivar: the lambda becomes a method on Media::Download, where ivars are the module's.
    downloads = @downloads = []
    @downloader = lambda do |url, path, max_bytes:|
      downloads << url
      File.binwrite(path, "remote image")
      path
    end
  end

  def render_with(ffmpeg)
    with_stubbed_method(Media::Download, :to_file, @downloader) do
      with_stubbed_new(Media::Ffmpeg, ffmpeg) { RenderVideoJob.perform_now(@project) }
    end
  end

  test "renders one clip per scene, adds narration, and attaches the video and thumbnail" do
    ffmpeg = FakeFfmpeg.new

    render_with(ffmpeg)

    @project.reload
    assert @project.rendered?
    assert @project.video.attached?
    assert @project.thumbnail.attached?
    assert_nil @project.render_error
    assert_equal [ "https://upload.wikimedia.org/a.jpg" ], @downloads
    assert_equal [ "remote image", "\x89PNG".b ], ffmpeg.clips.map { |clip| clip[:image] }
    assert_equal 600, ffmpeg.clips.sum { |clip| clip[:frames] }, "20 s at 30 fps"
    assert_nil ffmpeg.finish_args[:music_path]
    assert_equal 20_000, ffmpeg.finish_args[:duration_ms]
    assert_equal [ true, false ], ffmpeg.clips.map { |clip| clip[:zoom_in] }, "zoom alternates in and out"
  end

  test "mixes the music at its volume" do
    ready_music_track(@project, volume: 25)
    ffmpeg = FakeFfmpeg.new

    render_with(ffmpeg)

    assert ffmpeg.finish_args[:music_path].present?
    assert_in_delta 0.25, ffmpeg.finish_args[:music_volume]
  end

  test "a failure records the reason and returns the project to the music-approved step" do
    render_with(FakeFfmpeg.new(error: Media::Ffmpeg::Error.new("ffmpeg failed: bad image")))

    @project.reload
    assert @project.media_ready?
    assert_equal "ffmpeg failed: bad image", @project.render_error
    assert_not @project.video.attached?
  end

  test "a failed re-render keeps the earlier video" do
    attach_rendered_video(@project)
    @project.update!(status: "rendering")

    render_with(FakeFfmpeg.new(error: Media::Ffmpeg::Error.new("ffmpeg failed")))

    assert @project.reload.rendered?
    assert_equal "video.mp4", @project.video.filename.to_s
  end

  test "refuses to render while a scene has no image" do
    @project.scenes.first.images.update_all(selected: false)

    render_with(FakeFfmpeg.new)

    assert_equal "Every scene needs an image before rendering.", @project.reload.render_error
  end

  test "burns in captions from the narration, with the YouTube title as the hook" do
    @project.update!(yt_title: "Why the Sea Rises")
    @project.voice_track.update!(timings: [ { "text" => "Tides follow the moon.", "start_ms" => 0, "end_ms" => 20_000 } ])
    ffmpeg = FakeFfmpeg.new

    render_with(ffmpeg)

    assert ffmpeg.finish_args[:captions_path].end_with?("captions.ass")
    assert_includes ffmpeg.captions, "TIDES FOLLOW THE"
    assert_includes ffmpeg.captions, "Hook,,0,0,0,,{\\fad(0,400)}WHY THE SEA RISES"
    assert_nil @project.reload.settings["render_warning"]
  end

  test "skips captions with a warning when ffmpeg can't draw text" do
    ffmpeg = FakeFfmpeg.new(captions: false)

    render_with(ffmpeg)

    assert_nil ffmpeg.finish_args[:captions_path]
    assert @project.reload.rendered?
    assert_equal RenderVideoJob::CAPTIONS_SKIPPED, @project.settings["render_warning"]
  end

  test "renders without captions when they are turned off" do
    @project.update!(settings: @project.settings.merge("captions" => false))
    ffmpeg = FakeFfmpeg.new

    render_with(ffmpeg)

    assert_nil ffmpeg.finish_args[:captions_path]
    assert_nil @project.reload.settings["render_warning"]
  end

  test "a video scene is downloaded once and cut at the chosen start" do
    scene = @project.scenes.first
    scene.images.update_all(selected: false)
    scene.images.create!(provider: "wikimedia_commons", media_type: "video", image_url: "https://upload.wikimedia.org/refugees.webm",
                         poster_url: "https://upload.wikimedia.org/refugees.jpg", credit: "Archive", license: "Public domain",
                         duration_ms: 60_000, clip_start_ms: 15_000, selected: true)
    ffmpeg = FakeFfmpeg.new

    render_with(ffmpeg)

    first = ffmpeg.clips.first
    assert_not first[:video].start_with?("https://"), "the clip is cut from a local copy"
    assert_equal 15_000, first[:start_ms]
    assert_equal 300, first[:frames]
    assert_equal 1, @downloads.count("https://upload.wikimedia.org/refugees.webm")
    assert @project.reload.rendered?
  end

  test "a video used by two scenes is downloaded only once" do
    @project.scenes.each do |scene|
      scene.images.update_all(selected: false)
      scene.images.create!(provider: "wikimedia_commons", media_type: "video", image_url: "https://upload.wikimedia.org/same.webm",
                           poster_url: "https://upload.wikimedia.org/same.jpg", credit: "Archive", license: "Public domain",
                           duration_ms: 60_000, clip_start_ms: 0, selected: true)
    end

    render_with(FakeFfmpeg.new)

    assert_equal 1, @downloads.count("https://upload.wikimedia.org/same.webm")
    assert @project.reload.rendered?
  end
end
