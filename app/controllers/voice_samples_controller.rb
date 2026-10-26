class VoiceSamplesController < ApplicationController
  def create
    voice_name = params[:voice_name]
    return head :unprocessable_entity unless Ai::SpeechGenerator::VOICES.key?(voice_name)

    sample = VoiceSample.generate_for(voice_name)
    render_sample(voice_name, sample: sample, autoplay: true)
  rescue Ai::Error => e
    render_sample(voice_name, error: e.message)
  end

  private
    def render_sample(voice_name, **locals)
      render turbo_stream: turbo_stream.replace("voice_sample_#{voice_name}",
        partial: "voice_samples/sample", locals: { voice_name: voice_name, **locals })
    end
end
