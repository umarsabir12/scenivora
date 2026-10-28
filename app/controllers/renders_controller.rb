# The Render step: builds the MP4 locally with ffmpeg.
class RendersController < ApplicationController
  before_action :set_project
  before_action :require_media_ready

  def show
    @music = @project.music_track if @project.music_track&.ready?
    @captions_supported = Media::Ffmpeg.new.supports_captions?
  rescue Media::Ffmpeg::Error
    @captions_supported = false
  end

  def create
    if @project.rendering?
      redirect_to project_render_path(@project), notice: "The video is already rendering."
    else
      captions = params.key?(:captions) ? params[:captions] == "1" : @project.captions_enabled?
      @project.update!(status: :rendering, render_error: nil, settings: @project.settings.merge("captions" => captions))
      RenderVideoJob.perform_later(@project)
      redirect_to project_render_path(@project), notice: "Rendering started. This page updates as it goes."
    end
  end

  private
    def set_project
      @project = current_user.projects.find(params[:project_id])
    end

    def require_media_ready
      redirect_to project_music_path(@project), alert: "Finish the music step first." unless @project.media_approved?
    end
end
