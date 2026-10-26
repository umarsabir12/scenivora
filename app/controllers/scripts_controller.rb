class ScriptsController < ApplicationController
  before_action :set_project

  # Generates the first script, or a new version when called from "Rewrite".
  def create
    @project.start_script_generation!

    respond_to do |format|
      format.turbo_stream { render turbo_stream: script_panel_stream }
      format.html { redirect_to @project }
    end
  end

  # Autosave target: saves edits to the latest version in place.
  def update
    script = @project.latest_script
    return head :not_found unless script

    if script.update(body: params.expect(script: [ :body ])[:body])
      render json: { saved_at: script.updated_at.iso8601 }
    else
      render json: { errors: script.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private
    def set_project
      @project = current_user.projects.find(params[:project_id])
    end

    def script_panel_stream
      turbo_stream.replace(
        "script_panel",
        partial: "projects/script_panel",
        locals: { project: @project, error: nil }
      )
    end
end
