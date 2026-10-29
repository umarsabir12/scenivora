# Edits to a storyboard's narration, scene by scene. The script and the scene times follow, and
# a voice made before the edit has to be made again.
class StoryboardScenesController < ApplicationController
  MAX_TEXT = 1_000

  before_action :set_scene

  def update
    text = params.expect(scene: [ :text ])[:text].to_s.squish
    if text.empty? || text.length > MAX_TEXT
      return redirect_to(scenes_page, alert: "A scene needs between 1 and #{MAX_TEXT} characters of narration.")
    end

    @scene.update!(text: text)
    @project.storyboard_changed!
    redirect_to scenes_page, notice: "Scene #{@scene.position} saved."
  end

  def destroy
    return redirect_to(scenes_page, alert: "A video needs at least one scene.") if @project.scenes.count == 1

    position = @scene.position
    @scene.destroy!
    @project.storyboard_changed!
    redirect_to project_scenes_path(@project), notice: "Scene #{position} deleted."
  end

  private
    def set_scene
      @scene = Scene.joins(:project).where(projects: { user_id: current_user.id }).find(params[:id])
      @project = @scene.project
      redirect_to(project_scenes_path(@project), alert: "Wait until the storyboard is ready.") if @project.producing?
    end

    def scenes_page
      project_scenes_path(@project, scene: @scene.id)
    end
end
