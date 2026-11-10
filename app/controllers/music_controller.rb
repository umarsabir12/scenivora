# Music actions for the Render step: pick a suggested track from Wikimedia Commons or upload one, set
# its volume, or remove it. The music card is shown on the Render page.
class MusicController < ApplicationController
  COMMONS_FILE_HOST = "upload.wikimedia.org".freeze

  before_action :set_project
  before_action :require_voice_confirmed

  def show
    redirect_to render_page
  end

  # Uses a Commons track. The file is downloaded and measured in the background.
  def create
    url = params[:audio_url].to_s
    return redirect_to(render_page, alert: "That track can't be used.") unless commons_file?(url)

    track = replace_track(title: params[:title], credit: params[:credit], license: params[:license],
                          page_url: params[:page_url], source_url: url)
    if track.save
      PrepareMusicTrackJob.perform_later(track)
      redirect_to render_page, notice: "Preparing the track..."
    else
      redirect_to render_page, alert: track.errors.full_messages.to_sentence
    end
  end

  def upload
    file = params.require(:file)
    track = replace_track(title: File.basename(file.original_filename.to_s, ".*").first(120).presence || "Uploaded track",
                          credit: "Your upload", license: "Provided by you", page_url: nil, source_url: nil)
    track.file.attach(file)

    if track.save
      PrepareMusicTrackJob.perform_later(track)
      redirect_to render_page, notice: "Preparing your track..."
    else
      redirect_to render_page, alert: track.errors.full_messages.to_sentence
    end
  end

  def update
    track = @project.music_track
    return redirect_to(render_page, alert: "Choose a track first.") unless track

    if track.update(volume: params[:volume])
      redirect_to render_page, notice: "Volume set to #{track.volume}%."
    else
      redirect_to render_page, alert: track.errors.full_messages.to_sentence
    end
  end

  def destroy
    @project.music_track&.destroy!
    redirect_to render_page, notice: "Music removed. The video will have narration only."
  end

  private
    def set_project
      @project = current_user.projects.find(params[:project_id])
    end

    def require_voice_confirmed
      redirect_to project_voice_path(@project), alert: "Confirm the voice first." unless @project.music_available?
    end

    # The Render page hides the music card once the video is rendered; keep it open after a change.
    def render_page
      project_render_path(@project, music: (1 if @project.rendered?))
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
