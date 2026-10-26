require "tmpdir"

class GenerateVoiceJob < ApplicationJob
  queue_as :default

  # Encoded MP3 parts from a synthesis run, plus totals for usage tracking.
  Parts = Data.define(:audio, :characters, :cost_usd)

  def perform(track)
    project = track.project
    script = project.latest_script
    raise Ai::Error, "There is no script to narrate yet." unless script

    track.update!(status: :processing, error: nil, script_digest: script.digest)
    broadcast(track)

    parts = synthesize(script.body, track)
    duration_ms = attach_joined_audio(track, parts.audio)

    track.update!(status: :ready, duration_ms: duration_ms)
    project.update!(status: :voice_ready, settings: project.settings.merge("ai_voice" => true))
    record_usage(project, parts)
    refresh(track)
  rescue StandardError => e
    Rails.logger.error("Voice generation failed for track #{track.id}: #{e.class}: #{e.message}")
    track.update!(status: :failed, error: user_facing_error(e))
    refresh(track)
  end

  private
    def synthesize(text, track)
      chunks = NarrationChunker.new(text, limit: Ai::SpeechGenerator::MAX_INPUT_CHARACTERS).chunks
      generator = Ai::SpeechGenerator.new

      results = chunks.each_with_index.map do |chunk, index|
        broadcast(track, progress: "Generating part #{index + 1} of #{chunks.size}...")
        generator.call(text: chunk, voice: track.voice_name, speed: track.speed.to_f)
      end

      Parts.new(
        audio: results.map(&:audio),
        characters: results.sum(&:characters),
        cost_usd: results.sum(&:cost_usd)
      )
    end

    # Joins the parts with ffmpeg, attaches the result to the track, and returns its duration.
    def attach_joined_audio(track, audio_parts)
      Dir.mktmpdir("voice-track-#{track.id}") do |dir|
        part_paths = audio_parts.each_with_index.map do |bytes, index|
          path = File.join(dir, format("part-%03d.mp3", index + 1))
          File.binwrite(path, bytes)
          path
        end

        output_path = File.join(dir, "narration.mp3")
        ffmpeg = Media::Ffmpeg.new
        ffmpeg.concat(part_paths, output_path)

        File.open(output_path, "rb") do |io|
          track.file.attach(io: io, filename: "narration-project-#{track.project_id}.mp3", content_type: "audio/mpeg")
        end
        ffmpeg.duration_ms(output_path)
      end
    end

    def record_usage(project, parts)
      project.api_usages.create!(
        provider: Ai::SpeechGenerator::PROVIDER,
        operation: "voice",
        units: parts.characters,
        cost_usd: parts.cost_usd
      )
    end

    def user_facing_error(error)
      case error
      when Ai::Error, Media::Ffmpeg::Error then error.message
      else "Voice generation failed. Please try again."
      end
    end

    # Once the run finishes, reload the Voice tab so the Confirm button reflects the new state.
    def refresh(track)
      Turbo::StreamsChannel.broadcast_refresh_to([ track.project, :voice ])
    end

    def broadcast(track, progress: nil)
      Turbo::StreamsChannel.broadcast_replace_to(
        [ track.project, :voice ],
        target: "voice_panel",
        partial: "voices/panel",
        locals: { project: track.project, track: track, progress: progress }
      )
    end
end
