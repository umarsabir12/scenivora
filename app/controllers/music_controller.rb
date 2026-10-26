# Placeholder for the Music step. Reached after the scenes are approved.
class MusicController < ApplicationController
  before_action :set_project

  def show
  end

  private
    def set_project
      @project = current_user.projects.find(params[:project_id])
    end
end
