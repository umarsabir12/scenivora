# Writes the YouTube title, description, tags and category, then appends the credits footer.
class GenerateMetadataJob < ApplicationJob
  queue_as :default

  def perform(project)
    result = Ai::MetadataGenerator.new.call(topic: project.prompt, tone: project.tone, script: project.latest_script&.body)

    project.update!(
      yt_title: result.title,
      yt_description: VideoDescription.new(project).full(result.description),
      yt_tags: result.tags,
      yt_category: result.category,
      settings: project.settings.except("metadata_generating", "metadata_error")
    )
    project.api_usages.create!(provider: Ai::TextGenerator::PROVIDER, operation: "metadata",
                               units: result.total_tokens, cost_usd: result.cost_usd)
  rescue StandardError => e
    Rails.logger.error("Metadata failed for project #{project.id}: #{e.class}: #{e.message}")
    message = e.is_a?(Ai::Error) ? e.message : "Writing the details failed. Please try again."
    project.update!(settings: project.settings.except("metadata_generating").merge("metadata_error" => message))
  ensure
    Turbo::StreamsChannel.broadcast_refresh_to([ project, :publish ])
  end
end
