# The Music step: pick a free track from Wikimedia Commons or upload one, set its volume, or skip music.
class MusicController < ApplicationController
  DEFAULT_QUERIES = {
    "documentary" => "ambient documentary", "dramatic" => "cinematic dramatic",
    "inspirational" => "inspirational piano", "casual" => "acoustic background"
  }.freeze
  COMMONS_FILE_HOST = "upload.wikimedia.org".freeze

  before_action :set_project
  before_action :require_scenes_approved

  def show
    @track = @project.music_track
    @query = params[:q].presence || DEFAULT_QUERIES.fetch(@project.tone, "ambient background")
    @results = Rails.cache.fetch([ "commons_audio", @query ], expires_in: 1.hour) { Media::CommonsAudioSearch.new.search(@query) }
  rescue Media::Error => e
    Rails.logger.warn("Music search failed: #{e.message}")
    @results = []
    @search_error = "Music search failed. Try again later."
  end

  # Uses a Commons track. The file is downloaded and measured in the background.
  def create
    url = params[:audio_url].to_s
    return redirect_to(project_music_path(@project), alert: "That track can't be used.") unless commons_file?(url)

    track = replace_track(title: params[:title], credit: params[:credit], license: params[:license],
                          page_url: params[:page_url], source_url: url)
    if track.save
      PrepareMusicTrackJob.perform_later(track)
      redirect_to project_music_path(@project), notice: "Preparing the track..."
    else
      redirect_to project_music_path(@project), alert: track.errors.full_messages.to_sentence
    end
  end

  def upload
    file = params.require(:file)
    track = replace_track(title: File.basename(file.original_filename.to_s, ".*").first(120).presence || "Uploaded track",
                          credit: "Your upload", license: "Provided by you", page_url: nil, source_url: nil)
    track.file.attach(file)

    if track.save
      PrepareMusicTrackJob.perform_later(track)
      redirect_to project_music_path(@project), notice: "Preparing your track..."
    else
      redirect_to project_music_path(@project), alert: track.errors.full_messages.to_sentence
    end
  end

  def update
    track = @project.music_track
    return redirect_to(project_music_path(@project), alert: "Choose a track first.") unless track

    if track.update(volume: params[:volume])
      redirect_to project_music_path(@project), notice: "Volume set to #{track.volume}%."
    else
      redirect_to project_music_path(@project), alert: track.errors.full_messages.to_sentence
    end
  end

  def destroy
    @project.music_track&.destroy!
    redirect_to project_music_path(@project), notice: "Music removed. The video will have narration only."
  end

  # Music is optional. A track that is still being prepared must finish first.
  def continue
    track = @project.music_track
    if track && !track.ready? && !track.failed?
      return redirect_to(project_music_path(@project), alert: "Wait until the track is ready, or remove it.")
    end
    if track&.failed?
      return redirect_to(project_music_path(@project), alert: "The track could not be prepared. Choose another, or remove it.")
    end

    @project.media_ready! unless @project.media_approved?
    redirect_to project_render_path(@project)
  end

  private
    def set_project
      @project = current_user.projects.find(params[:project_id])
    end

    def require_scenes_approved
      redirect_to project_scenes_path(@project), alert: "Approve the scenes first." unless @project.scenes_approved?
    end

    def commons_file?(url)
      uri = URI(url)
      uri.is_a?(URI::HTTPS) && uri.host == COMMONS_FILE_HOST
    rescue URI::InvalidURIError
      false
    end

    # A project has one music track; choosing another replaces it.
    def replace_track(**attributes)
      track = @project.music_track || @project.build_music_track
      track.file.purge if track.persisted? && track.file.attached?
      track.assign_attributes(attributes.merge(status: :pending, error: nil, duration_ms: nil))
      track
    end
end
