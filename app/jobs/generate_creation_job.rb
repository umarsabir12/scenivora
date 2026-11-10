require "tmpdir"

# Makes one single-tool creation. Credits were charged when the user asked for it; they are
# refunded here if it fails. Only speech has a model so far.
class GenerateCreationJob < ApplicationJob
  queue_as :default

  def perform(creation)
    return unless creation.pending?

    creation.update!(status: :processing, error: nil)
    refresh(creation)

    case creation.kind
    when "speech" then make_speech(creation)
    else raise Ai::Error, "#{creation.kind.capitalize} has no model yet."
    end

    creation.update!(status: :ready)
  rescue StandardError => e
    Rails.logger.error("Creation #{creation.id} failed: #{e.class}: #{e.message}")
    refund(creation)
    creation.update!(status: :failed, error: user_facing_error(e))
  ensure
    refresh(creation)
  end

  private
    # Long text is voiced in parts at sentence breaks, then joined into one MP3.
    def make_speech(creation)
      chunks = NarrationParts.new(creation.prompt, limit: Ai::SpeechGenerator::MAX_INPUT_CHARACTERS).parts
      generator = Ai::SpeechGenerator.new(model: creation.model.model)
      results = chunks.map { |chunk| generator.call(text: chunk, voice: creation.voice, speed: creation.speed) }

      creation.api_usages.create!(provider: creation.model.provider, operation: "create_speech",
                                  units: results.sum(&:characters), cost_usd: results.sum(&:cost_usd))

      Dir.mktmpdir("creation-#{creation.id}") do |dir|
        paths = results.each_with_index.map do |result, index|
          File.join(dir, format("part-%03d.mp3", index + 1)).tap { |path| File.binwrite(path, result.audio) }
        end
        output = File.join(dir, "speech.mp3")
        ffmpeg = Media::Ffmpeg.new
        ffmpeg.concat(paths, output)

        File.open(output, "rb") do |io|
          creation.file.attach(io: io, filename: "speech-#{creation.id}.mp3", content_type: "audio/mpeg")
        end
        creation.update!(duration_ms: ffmpeg.duration_ms(output))
      end
    end

    def refund(creation)
      return unless creation.credits_charged.positive?

      creation.user.grant_credits!(creation.credits_charged, reason: "create_#{creation.kind}_refund")
    end

    def user_facing_error(error)
      case error
      when Ai::Error, Media::Ffmpeg::Error then error.message
      else "Something went wrong. Your credits were refunded."
      end
    end

    def refresh(creation)
      Turbo::StreamsChannel.broadcast_refresh_to([ creation.user, :creations ])
    end
end
