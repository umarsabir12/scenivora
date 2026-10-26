# Placeholder for the Scenes step. The screen is reachable after the voice is confirmed,
# but scene generation and image review are not built yet.
class ScenesController < ApplicationController
  before_action :set_project

  def show
  end

  private
    def set_project
      @project = current_user.projects.find(params[:project_id])
    end
end
