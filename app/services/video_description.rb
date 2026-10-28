# Builds the credits and disclosures that go under the AI-written description. Built from the
# project's data, not by the model, so it is always accurate.
class VideoDescription
  def initialize(project)
    @project = project
  end

  def footer
    [ disclosures, image_credits, music_credit ].compact_blank.join("\n\n")
  end

  # The AI description followed by the footer.
  def full(ai_description)
    [ ai_description.to_s.strip, footer ].compact_blank.join("\n\n")
  end

  private
    def selected_images
      @selected_images ||= @project.scenes.includes(:images).filter_map(&:selected_image)
    end

    def disclosures
      lines = []
      lines << "Narration is AI-generated." if @project.settings["ai_voice"]
      lines << "Some images are AI-generated." if selected_images.any?(&:ai?)
      lines.join("\n")
    end

    def image_credits
      sourced = selected_images.reject(&:stored_file?).uniq(&:image_url)
      return if sourced.empty?

      lines = sourced.map { |image| "- #{[ image.credit, image.license, image.page_url ].compact_blank.join(", ")}" }
      heading = sourced.any?(&:video?) ? "Image and video credits" : "Image credits"
      "#{heading}:\n#{lines.join("\n")}"
    end

    def music_credit
      track = @project.music_track
      return unless track&.ready? && track.source_url.present?

      "Music: #{[ track.title, track.credit, track.license, track.page_url ].compact_blank.join(", ")}"
    end
end
