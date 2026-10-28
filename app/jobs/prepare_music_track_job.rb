require "tmpdir"

# Makes a chosen music track ready to render: downloads it (Commons picks) and measures its length.
class PrepareMusicTrackJob < ApplicationJob
  queue_as :default

  def perform(track)
    track.update!(status: :processing, error: nil)

    Dir.mktmpdir("music-track-#{track.id}") do |dir|
      path = File.join(dir, "music")
      if track.file.attached?
        File.binwrite(path, track.file.download)
      else
        Media::Download.to_file(track.source_url, path, max_bytes: AudioTrack::MAX_MUSIC_BYTES)
        # No content type given: Active Storage detects it from the file itself.
        track.file.attach(io: File.open(path, "rb"), filename: download_filename(track))
      end

      track.update!(status: :ready, duration_ms: Media::Ffmpeg.new.duration_ms(path))
    end
  rescue StandardError => e
    Rails.logger.error("Music track #{track.id} failed: #{e.class}: #{e.message}")
    track.update_columns(status: "failed", error: user_facing_error(e))
  ensure
    Turbo::StreamsChannel.broadcast_refresh_to([ track.project, :music ])
  end

  private
    def download_filename(track)
      "#{track.title.parameterize.presence || "music"}#{File.extname(URI(track.source_url).path)}"
    end

    def user_facing_error(error)
      case error
      when Media::Error, Media::Ffmpeg::Error then error.message
      when ActiveRecord::RecordInvalid then error.record.errors.full_messages.to_sentence
      else "The track could not be prepared."
      end
    end
end
