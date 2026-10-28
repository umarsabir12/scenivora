# The Scenes step: splits the confirmed narration into timed scenes and finds free images for each.
class ScenesController < ApplicationController
  before_action :set_project

  def show
    @scenes = @project.scenes.includes(images: { file_attachment: :blob }).to_a
    @track = @project.voice_track
    @current_scene = @scenes.find { |scene| scene.id == params[:scene].to_i } ||
                     @scenes.find { |scene| scene.selected_image.nil? } || @scenes.first
    @source = params[:source].presence_in(%w[video ai]) || "commons"
  end

  # Charges for and starts an AI image in every scene where one is suggested, all or nothing.
  def generate_suggested
    scenes = @project.scenes.select { |scene| scene.ai_suggested? && !scene.ai_generating? }
    return redirect_to(project_scenes_path(@project), alert: "No scenes are waiting for an AI image.") if scenes.empty?

    total = scenes.size * CreditPricing.ai_image
    if current_user.credits_balance < total
      return redirect_to(project_scenes_path(@project),
        alert: "#{helpers.pluralize(scenes.size, "AI image")} need #{total} credits. You have #{current_user.credits_balance}.")
    end

    started = scenes.count { |scene| scene.start_ai_image!(current_user, scene.suggested_ai_prompt) }
    redirect_to project_scenes_path(@project),
      notice: "Generating #{helpers.pluralize(started, "AI image")}. #{started * CreditPricing.ai_image} credits charged."
  rescue User::InsufficientCredits
    redirect_to project_scenes_path(@project), alert: "Not enough credits to finish. Some images may have started."
  end

  # Every scene needs an image before the project moves on to music.
  def approve
    scenes = @project.scenes.includes(:images).to_a
    missing = scenes.reject(&:selected_image)

    if scenes.empty?
      redirect_to project_scenes_path(@project), alert: "Create scenes before approving them."
    elsif missing.any?
      redirect_to project_scenes_path(@project, scene: missing.first.id),
        alert: "#{helpers.pluralize(missing.size, "scene")} still need an image."
    else
      @project.scenes_ready!
      redirect_to project_music_path(@project), notice: "Scenes approved. Next: music."
    end
  end

  def create
    track = @project.voice_track

    if track.nil? || !track.confirmed?
      redirect_to project_voice_path(@project), alert: "Confirm the voice before creating scenes."
    elsif track.stale_for?(@project.latest_script)
      redirect_to project_voice_path(@project), alert: "The script changed since the voice was confirmed. Regenerate and confirm the voice first."
    elsif @project.settings["scenes_searching"]
      redirect_to project_scenes_path(@project), notice: "Already finding images."
    else
      mode = params[:image_mode].presence_in(Project::IMAGE_MODES) || @project.image_mode
      @project.update!(settings: @project.settings.merge("scenes_searching" => true, "image_mode" => mode))
      FindSceneImagesJob.perform_later(@project)
      redirect_to project_scenes_path(@project), notice: "Finding images for each scene. This page refreshes when it's done."
    end
  end

  private
    def set_project
      @project = current_user.projects.find(params[:project_id])
    end
end
