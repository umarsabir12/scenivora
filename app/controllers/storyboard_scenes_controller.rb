# Edits to a storyboard, scene by scene: narration (saved as the user types), deleting a scene and
# adding an empty one. The script and the scene times follow, and a voice made before the edit has
# to be made again.
class StoryboardScenesController < ApplicationController
  MAX_TEXT = 1_000

  before_action :set_scene

  # Narration may be empty while the user writes it; approving the storyboard asks for it. Answers
  # the page's autosave with every scene's new start time, since one scene's length moves the rest.
  def update
    text = params.expect(scene: [ :text ])[:text].to_s.squish
    if text.length > MAX_TEXT
      message = "A scene's narration can be at most #{MAX_TEXT} characters."
      return respond_to do |format|
        format.html { redirect_to scenes_page, alert: message }
        format.json { render json: { error: message }, status: :unprocessable_content }
      end
    end

    @scene.update!(text: text)
    @project.storyboard_changed!
    respond_to do |format|
      format.html { redirect_to scenes_page, notice: "Scene #{@scene.position} saved." }
      format.json { render json: timings }
    end
  end

  def destroy
    return redirect_to(scenes_page, alert: "A video needs at least one scene.") if @project.scenes.count == 1

    position = @scene.position
    @scene.destroy!
    @project.storyboard_changed!
    redirect_back_to_storyboard notice: "Scene #{position} deleted."
  end

  # An empty scene right after this one, for the user to write and give a picture (upload or AI).
  # Later scenes move down from the end, since no two scenes may share a position.
  def add_after
    added = Scene.transaction do
      @project.scenes.where("position > ?", @scene.position).reorder(position: :desc).each do |later|
        later.update!(position: later.position + 1)
      end
      @project.scenes.create!(position: @scene.position + 1, text: "", start_ms: @scene.end_ms,
                              duration_ms: StoryboardScenes::MIN_DURATION_MS)
    end
    @project.storyboard_changed!
    flash[:new_scene_id] = added.id
    redirect_back_to_storyboard notice: "Scene #{added.position} added. Write its narration, then upload or generate a picture."
  end

  private
    def set_scene
      @scene = Scene.joins(:project).where(projects: { user_id: current_user.id }).find(params[:id])
      @project = @scene.project
      if @project.producing?
        redirect_to(project_scenes_path(@project), alert: "Wait until the storyboard is ready.")
      elsif !@project.storyboard?
        redirect_to(project_scenes_path(@project), alert: "Only a storyboard's scenes can be edited here.")
      end
    end

    def scenes_page
      project_scenes_path(@project, scene: @scene.id)
    end

    # Back to the storyboard address the user was on: the same address counts as a page refresh, so
    # Turbo morphs the page and keeps the scroll position instead of jumping to the top. An address
    # naming a deleted scene still works: the page opens another scene in the side panel.
    def redirect_back_to_storyboard(notice:)
      back = request.referer.to_s
      redirect_to(back.start_with?(project_scenes_url(@project)) ? back : project_scenes_path(@project), notice: notice)
    end

    def timings
      scenes = @project.scenes.reload
      { starts: scenes.to_h { |scene| [ scene.id, helpers.format_timecode(scene.start_ms) ] },
        length: helpers.format_timecode(scenes.last.end_ms) }
    end
end
