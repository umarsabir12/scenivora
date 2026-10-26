# The Scenes step: splits the confirmed narration into timed scenes and finds free images for each.
class ScenesController < ApplicationController
  before_action :set_project

  def show
    @scenes = @project.scenes.includes(images: { file_attachment: :blob }).to_a
    @track = @project.voice_track
    @current_scene = @scenes.find { |scene| scene.id == params[:scene].to_i } ||
                     @scenes.find { |scene| scene.selected_image.nil? } || @scenes.first
    @source = params[:source] == "ai" ? "ai" : "commons"
  end

  # Every scene needs an image before the project moves on to music.
  def approve
    scenes = @project.scenes.includes(:images).to_a
    missing = scenes.reject(&:selected_image)

    if scenes.empty?
      redirect_to project_scenes_path(@project), alert: "Create scenes before approving them."
    elsif missing.any?
      redirect_to project_scenes_path(@project, scene: missing.first.id, anchor: "swap"),
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
      @project.update!(settings: @project.settings.merge("scenes_searching" => true))
      FindSceneImagesJob.perform_later(@project)
      redirect_to project_scenes_path(@project), notice: "Finding images for each scene. This page refreshes when it's done."
    end
  end

  private
    def set_project
      @project = current_user.projects.find(params[:project_id])
    end
end
