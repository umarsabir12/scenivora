class ProjectsController < ApplicationController
  FILTERS = %w[in_progress rendered].freeze

  before_action :set_project, only: :show

  def index
    @filter = params[:filter].presence_in(FILTERS)
    @projects = filtered(current_user.projects.order(created_at: :desc))
    @new_project = current_user.projects.build(tone: "documentary", target_length_minutes: 6)
  end

  def show
  end

  def new
    @project = current_user.projects.build(tone: "documentary", target_length_minutes: 6)
  end

  # Called from the dashboard composer with generate=1, which also starts the script.
  def create
    @project = current_user.projects.build(project_params)

    if @project.save
      @project.start_script_generation! if params[:generate].present?
      redirect_to @project, notice: "Project created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def set_project
      @project = current_user.projects.find(params[:id])
    end

    def project_params
      params.expect(project: %i[prompt tone target_length_minutes])
    end

    def filtered(scope)
      case @filter
      when "in_progress" then scope.where.not(status: "rendered")
      when "rendered" then scope.rendered
      else scope
      end
    end
end
