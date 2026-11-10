# The Render step: optional background music, then the MP4 built locally with ffmpeg, then publish.
class RendersController < ApplicationController
  MUSIC_QUERIES = {
    "documentary" => "ambient documentary", "dramatic" => "cinematic dramatic",
    "inspirational" => "inspirational piano", "casual" => "acoustic background"
  }.freeze

  before_action :set_project
  before_action :require_voice_confirmed

  def show
    @music = @project.music_track if @project.music_track&.ready?
    # Once the video is rendered the music card is hidden; "Change" (?music=1) brings it back for a re-render.
    @show_music = !(@project.rendered? && @project.video.attached?) || params[:music].present?
    load_music_suggestions if @show_music && !@project.rendering?
    @captions_supported = begin
      Media::Ffmpeg.new.supports_captions?
    rescue Media::Ffmpeg::Error
      false
    end
  end

  # Music is optional, but a chosen track must be ready first.
  def create
    track = @project.music_track
    if @project.rendering?
      redirect_to project_render_path(@project), notice: "The video is already rendering."
    elsif track&.failed?
      redirect_to project_render_path(@project), alert: "The music track could not be prepared. Choose another, or remove it."
    elsif track && !track.ready?
      redirect_to project_render_path(@project), alert: "Wait until the music track is ready, or remove it."
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

    def require_voice_confirmed
      redirect_to project_voice_path(@project), alert: "Confirm the voice first." unless @project.music_available?
    end

    # Free Commons tracks picked for the video's tone. There is no search box; uploads cover the rest.
    def load_music_suggestions
      query = MUSIC_QUERIES.fetch(@project.tone, "ambient background")
      @music_results = Rails.cache.fetch([ "commons_audio", query ], expires_in: 1.hour) do
        Media::CommonsAudioSearch.new.search(query)
      end
    rescue Media::Error => e
      Rails.logger.warn("Music search failed: #{e.message}")
      @music_results = []
      @music_search_error = "Suggested tracks couldn't load. Upload your own, or try again later."
    end
end
