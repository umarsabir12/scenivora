class VoicesController < ApplicationController
  before_action :set_project
  before_action :require_script

  # The Voice tab: the generated voice (with Regenerate and Confirm) above the narration voice box.
  def show
    @track = @project.voice_track || @project.build_voice_track(voice_name: default_voice, speed: 1.0)
    @samples = VoiceSample.where(voice_name: Ai::SpeechGenerator::VOICES.keys).index_by(&:voice_name)
  end

  # Generates the narration. Also used for "Regenerate" and "Retry" (which send no params and reuse the stored settings).
  def create
    track = @project.voice_track || @project.build_voice_track
    track.assign_attributes(voice_settings)
    track.voice_name ||= default_voice
    track.speed ||= 1.0
    track.status = :pending
    track.error = nil
    track.confirmed_at = nil
    track.save!

    GenerateVoiceJob.perform_later(track)
    redirect_to project_voice_path(@project)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to project_voice_path(@project), alert: e.record.errors.full_messages.to_sentence
  end

  def confirm
    track = @project.voice_track

    if track.nil? || !track.ready?
      redirect_to project_voice_path(@project), alert: "Generate a voice before confirming it."
    elsif track.stale_for?(@project.latest_script)
      redirect_to project_voice_path(@project), alert: "The script changed since this voice was generated. Regenerate it first."
    else
      track.update!(confirmed_at: Time.current)
      redirect_to project_scenes_path(@project), notice: "Voice confirmed. Next: scenes."
    end
  end

  private
    def set_project
      @project = current_user.projects.find(params[:project_id])
    end

    def require_script
      return if @project.voice_available?

      redirect_to project_path(@project), alert: "Generate a script before choosing a voice."
    end

    def default_voice
      Ai::SpeechGenerator::VOICES.keys.first
    end

    def voice_settings
      params.fetch(:audio_track, {}).permit(:voice_name, :speed)
    end
end
