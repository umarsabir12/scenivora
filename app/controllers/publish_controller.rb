# The Publish step: download the video and thumbnail, and write the YouTube details. The same panel
# sits on the Render page, so saving or writing details returns to whichever page sent the form.
class PublishController < ApplicationController
  before_action :set_project
  before_action :require_rendered

  def show
  end

  def update
    details = params.expect(project: %i[yt_title yt_description yt_tags yt_category])
    details[:yt_tags] = details[:yt_tags].to_s.split(",").map(&:squish).reject(&:empty?)

    if @project.update(details)
      redirect_back_or_to project_publish_path(@project), notice: "Details saved."
    else
      redirect_back_or_to project_publish_path(@project), alert: @project.errors.full_messages.to_sentence
    end
  end

  def generate
    if @project.settings["metadata_generating"]
      return redirect_back_or_to(project_publish_path(@project), notice: "The details are already being written.")
    end

    @project.update!(settings: @project.settings.except("metadata_error").merge("metadata_generating" => true))
    GenerateMetadataJob.perform_later(@project)
    redirect_back_or_to project_publish_path(@project), notice: "Writing the YouTube details..."
  end

  # SRT captions to upload to YouTube as a caption track.
  def captions
    words = Captions::WordTimings.new(@project.voice_track, @project.latest_script).words
    send_data Captions::Srt.new(words).to_s, filename: "#{@project.title.parameterize.first(60)}.srt",
                                             type: "application/x-subrip", disposition: "attachment"
  end

  private
    def set_project
      @project = current_user.projects.find(params[:project_id])
    end

    # The current video stays publishable while a re-render runs.
    def require_rendered
      ready = (@project.rendered? || @project.rendering?) && @project.video.attached?
      redirect_to project_render_path(@project), alert: "Render the video first." unless ready
    end
end
