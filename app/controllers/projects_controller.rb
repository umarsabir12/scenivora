class ProjectsController < ApplicationController
  FILTERS = %w[in_progress rendered].freeze

  before_action :set_project, only: :show

  def index
    @filter = params[:filter].presence_in(FILTERS)
    @projects = filtered(current_user.projects.order(created_at: :desc))
    @new_project = current_user.projects.build(tone: "documentary", target_length_minutes: 6, category: "history")
  end

  # A project opens on its storyboard.
  def show
    redirect_to project_scenes_path(@project)
  end

  def new
    @project = current_user.projects.build(tone: "documentary", target_length_minutes: 6, category: "history")
  end

  # "Create video": saves the brief and starts research, script, scenes and pictures, then opens
  # the storyboard, which shows the progress.
  def create
    @project = current_user.projects.build(project_params)

    if @project.save
      @project.start_production!
      redirect_to project_scenes_path(@project), notice: "Creating your video. This page updates as it goes."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def set_project
      @project = current_user.projects.find(params[:id])
    end

    def project_params
      params.expect(project: %i[prompt tone target_length_minutes category instructions])
    end

    def filtered(scope)
      case @filter
      when "in_progress" then scope.where.not(status: "rendered")
      when "rendered" then scope.rendered
      else scope
      end
    end
end
