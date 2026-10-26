# Generates an AI image for one scene. Credits were charged when the user asked for it;
# they are refunded here if generation fails.
class GenerateSceneImageJob < ApplicationJob
  queue_as :default

  def perform(scene, prompt, credits_charged)
    project = scene.project
    result = Ai::ImageGenerator.new.call(prompt: prompt)

    image = scene.images.build(provider: SceneImage::AI_PROVIDER, credit: "AI generated", license: "AI generated",
                               prompt: prompt)
    image.file.attach(io: StringIO.new(result.image), filename: "scene-#{scene.id}-ai.png", content_type: result.content_type)
    image.save!
    image.select!

    project.api_usages.create!(provider: result.provider, operation: "ai_image", units: 1, cost_usd: result.cost_usd)
    project.update!(settings: project.settings.merge("ai_images" => true))
    scene.update!(ai_status: nil, ai_error: nil, search_error: nil)
  rescue StandardError => e
    Rails.logger.error("AI image failed for scene #{scene.id}: #{e.class}: #{e.message}")
    scene.project.user.grant_credits!(credits_charged, reason: "ai_image_refund", project: scene.project)
    scene.update!(ai_status: "failed", ai_error: e.is_a?(Ai::Error) ? e.message : "Image generation failed.")
  ensure
    Turbo::StreamsChannel.broadcast_refresh_to([ scene.project, :scenes ])
  end
end
