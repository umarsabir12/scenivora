require "tmpdir"

# Renders the final MP4 with ffmpeg: one zooming clip per scene, burned-in captions, the narration,
# and background music ducked underneath. Also makes a thumbnail. Runs locally, so it costs no API money.
class RenderVideoJob < ApplicationJob
  queue_as :default

  FPS = 30
  MAX_IMAGE_BYTES = 30.megabytes

  class RenderError < StandardError; end

  CAPTIONS_SKIPPED = "Captions were skipped: this ffmpeg can't draw text (it has no libass). " \
                     "Install it with `brew install ffmpeg-full`, then render again.".freeze

  def perform(project)
    voice = project.voice_track
    raise RenderError, "The narration is not ready." unless voice&.ready? && voice.file.attached?

    scenes = project.scenes.includes(images: { file_attachment: :blob }).to_a
    raise RenderError, "Every scene needs an image before rendering." if scenes.empty? || scenes.any? { |scene| scene.selected_image.nil? }

    music = project.music_track if project.music_track&.ready?
    ffmpeg = Media::Ffmpeg.new

    Dir.mktmpdir("render-#{project.id}") do |dir|
      clips = scenes.each_with_index.map do |scene, index|
        progress(project, "Preparing scene #{index + 1} of #{scenes.size}...")
        image_path = fetch_image(scene.selected_image, File.join(dir, format("image-%03d", index + 1)))
        ffmpeg.still_clip(image_path, frames_for(scene), File.join(dir, format("clip-%03d.mp4", index + 1)),
                          fps: FPS, zoom_in: index.even?)
      end

      progress(project, "Joining scenes...")
      video_path = ffmpeg.concat(clips, File.join(dir, "video.mp4"))

      captions_path = write_captions(project, voice, ffmpeg, File.join(dir, "captions.ass"))

      progress(project, captions_path ? "Adding captions, narration and music..." : "Adding narration and music...")
      final_path = ffmpeg.finish(
        video_path: video_path,
        narration_path: write_blob(voice.file, File.join(dir, "narration")),
        music_path: (write_blob(music.file, File.join(dir, "music")) if music),
        music_volume: music ? music.volume / 100.0 : 0.0,
        duration_ms: scenes.last.end_ms,
        captions_path: captions_path,
        output_path: File.join(dir, "final.mp4")
      )
      thumbnail_path = ffmpeg.thumbnail(final_path, File.join(dir, "thumbnail.jpg"))

      progress(project, "Saving the video...")
      project.video.attach(io: File.open(final_path, "rb"), filename: "#{project.title.parameterize.first(60)}.mp4", content_type: "video/mp4")
      project.thumbnail.attach(io: File.open(thumbnail_path, "rb"), filename: "#{project.title.parameterize.first(60)}-thumbnail.jpg", content_type: "image/jpeg")
    end

    project.update!(status: :rendered, render_error: nil)
  rescue StandardError => e
    Rails.logger.error("Render failed for project #{project.id}: #{e.class}: #{e.message}")
    # Keep an earlier render available if there is one.
    project.update!(status: project.video.attached? ? :rendered : :media_ready, render_error: user_facing_error(e))
  ensure
    Turbo::StreamsChannel.broadcast_refresh_to([ project, :render ])
  end

  private
    # Writes the caption file, or returns nil when captions are off or ffmpeg can't draw them.
    def write_captions(project, voice, ffmpeg, path)
      settings = project.settings.except("render_warning")
      unless project.captions_enabled?
        project.update!(settings: settings)
        return
      end
      unless ffmpeg.supports_captions?
        project.update!(settings: settings.merge("render_warning" => CAPTIONS_SKIPPED))
        return
      end

      project.update!(settings: settings)
      words = Captions::WordTimings.new(voice, project.latest_script).words
      Captions::AssBuilder.new(words, hook: project.yt_title).write(path)
    end

    # Frame counts come from each scene's start and end, so the clips add up to the narration exactly.
    def frames_for(scene)
      [ (scene.end_ms * FPS / 1000.0).round - (scene.start_ms * FPS / 1000.0).round, 1 ].max
    end

    def fetch_image(image, path)
      if image.stored_file?
        write_blob(image.file, path)
      else
        Media::Download.to_file(image.image_url, path, max_bytes: MAX_IMAGE_BYTES)
      end
    end

    def write_blob(attachment, path)
      File.binwrite(path, attachment.download)
      path
    end

    def progress(project, message)
      Turbo::StreamsChannel.broadcast_replace_to(
        [ project, :render ], target: "render_progress", partial: "renders/progress", locals: { message: message }
      )
    end

    def user_facing_error(error)
      case error
      when RenderError, Media::Error, Media::Ffmpeg::Error then error.message
      else "Rendering failed. Please try again."
      end
    end
end
