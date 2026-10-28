module PublishHelper
  # Everything a creator pastes into YouTube Studio, as one block of text.
  def youtube_details_text(project)
    [
      "Title:\n#{project.yt_title}",
      "Description:\n#{project.yt_description}",
      "Tags:\n#{project.yt_tags.join(", ")}",
      "Category:\n#{project.yt_category}"
    ].join("\n\n")
  end
end
