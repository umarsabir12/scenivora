# The Publish step: download the video and thumbnail, and write the YouTube details.
class PublishController < ApplicationController
  before_action :set_project
  before_action :require_rendered

  def show
  end

  def update
    details = params.expect(project: %i[yt_title yt_description yt_tags yt_category])
    details[:yt_tags] = details[:yt_tags].to_s.split(",").map(&:squish).reject(&:empty?)

    if @project.update(details)
      redirect_to project_publish_path(@project), notice: "Details saved."
    else
      redirect_to project_publish_path(@project), alert: @project.errors.full_messages.to_sentence
    end
  end

  def generate
    if @project.settings["metadata_generating"]
      return redirect_to(project_publish_path(@project), notice: "The details are already being written.")
    end

    @project.update!(settings: @project.settings.except("metadata_error").merge("metadata_generating" => true))
    GenerateMetadataJob.perform_later(@project)
    redirect_to project_publish_path(@project), notice: "Writing the YouTube details..."
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

    def require_rendered
      redirect_to project_render_path(@project), alert: "Render the video first." unless @project.rendered? && @project.video.attached?
    end
end
