require "tmpdir"

class GenerateVoiceJob < ApplicationJob
  queue_as :default

  # Encoded MP3 parts from a synthesis run, the text of each part, and totals for usage tracking.
  Parts = Data.define(:audio, :texts, :characters, :cost_usd)

  def perform(track)
    project = track.project
    script = project.latest_script
    raise Ai::Error, "There is no script to narrate yet." unless script

    track.update!(status: :processing, error: nil, script_digest: script.digest)
    broadcast(track)

    parts = synthesize(script.body, track)
    duration_ms, timings = attach_joined_audio(track, parts)

    track.update!(status: :ready, duration_ms: duration_ms, timings: timings)
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
      chunks = NarrationParts.new(text, limit: Ai::SpeechGenerator::MAX_INPUT_CHARACTERS).parts
      generator = Ai::SpeechGenerator.new

      results = chunks.each_with_index.map do |chunk, index|
        broadcast(track, progress: "Generating part #{index + 1} of #{chunks.size}...")
        generator.call(text: chunk, voice: track.voice_name, speed: track.speed.to_f)
      end

      Parts.new(
        audio: results.map(&:audio),
        texts: chunks,
        characters: results.sum(&:characters),
        cost_usd: results.sum(&:cost_usd)
      )
    end

    # Joins the parts with ffmpeg, attaches the result to the track, and returns its duration and
    # the timing of each part.
    def attach_joined_audio(track, parts)
      Dir.mktmpdir("voice-track-#{track.id}") do |dir|
        part_paths = parts.audio.each_with_index.map do |bytes, index|
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
        total_ms = ffmpeg.duration_ms(output_path)
        [ total_ms, part_timings(parts.texts, part_paths.map { |path| ffmpeg.duration_ms(path) }, total_ms) ]
      end
    end

    # Start and end of each part. Part lengths are scaled to the joined file's length, which can
    # differ slightly because of MP3 frame padding at each join.
    def part_timings(texts, part_ms, total_ms)
      scale = part_ms.sum.positive? ? total_ms.to_f / part_ms.sum : 1.0
      start_ms = 0
      texts.zip(part_ms).each_with_index.map do |(text, ms), index|
        end_ms = index == texts.size - 1 ? total_ms : start_ms + (ms * scale).round
        timing = { "text" => text, "start_ms" => start_ms, "end_ms" => end_ms }
        start_ms = end_ms
        timing
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
