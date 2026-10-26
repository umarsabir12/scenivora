# Splits the confirmed narration into scenes, plans a search for each one with a single
# planner call, then finds free candidate images. The planner runs only when the script or the
# narration length has changed, so repeated clicks don't pay for the same plan twice.
class FindSceneImagesJob < ApplicationJob
  queue_as :default

  MAX_CANDIDATES = 3
  PLANNING_FAILED = "Scene planning failed. Create scene again to retry.".freeze

  def perform(project)
    track = project.voice_track
    raise Ai::Error, "Confirm the voice before finding scene images." unless track&.confirmed?

    prepare_scenes(project, track)
    # Reload: the association still holds the scenes built before planning added their queries.
    project.scenes.reload.each { |scene| find_images(scene) }
  ensure
    project.update!(settings: project.settings.except("scenes_searching"))
    Turbo::StreamsChannel.broadcast_refresh_to([ project, :scenes ])
  end

  private
    # Identifies "this script at this length". Scenes and plans are reused while it stays the same.
    def scene_key(project, track)
      Digest::SHA256.hexdigest("#{project.latest_script.digest}:#{track.duration_ms}")
    end

    def prepare_scenes(project, track)
      key = scene_key(project, track)
      return if project.settings["scene_key"] == key && project.scenes.exists?

      split_scenes(project, track)
      return unless plan_scenes(project)

      project.update!(settings: project.settings.merge("scene_key" => key))
    end

    def split_scenes(project, track)
      Scene.transaction do
        project.scenes.destroy_all
        NarrationScenes.new(project.latest_script.body, track.duration_ms).scenes.each do |scene|
          project.scenes.create!(position: scene.position, text: scene.text, start_ms: scene.start_ms,
                                 duration_ms: scene.duration_ms)
        end
      end
    end

    # One planner call for the whole project. Returns false if planning failed.
    def plan_scenes(project)
      scenes = project.scenes.order(:position).to_a
      result = Ai::ScenePlanner.new.call(topic: project.prompt, scenes: scenes)
      record_usage(project, result)

      scenes.each do |scene|
        plan = result.plans.fetch(scene.position)
        scene.update!(search_query: plan.search_queries.first, plan: plan.to_h.except(:position))
      end
      true
    rescue Ai::Error => e
      Rails.logger.warn("Scene planning failed for project #{project.id}: #{e.message}")
      scenes&.each { |scene| scene.update!(search_error: PLANNING_FAILED) }
      false
    end

    def record_usage(project, result)
      project.api_usages.create!(provider: Ai::TextGenerator::PROVIDER, operation: "scene_plan",
                                 units: result.total_tokens, cost_usd: result.cost_usd)
    end

    def find_images(scene)
      # Without a plan there is nothing to search for. The error was set when planning failed.
      if scene.search_query.blank?
        scene.update!(search_error: "No search terms for this scene. Create scene again to retry.") if scene.search_error.blank?
        return
      end

      candidates = candidates_for(scene.search_query)
      scene.images.destroy_all
      candidates.each_with_index do |result, index|
        scene.images.create!(provider: result.provider, image_url: result.image_url, page_url: result.page_url,
                             credit: result.credit, license: result.license, selected: index.zero?)
      end
      scene.update!(search_error: nil)
    rescue Media::Error => e
      Rails.logger.warn("Image search failed for scene #{scene.id}: #{e.message}")
      scene.update!(search_error: "Image search failed. Try again later.")
    end

    def candidates_for(query)
      results = Media::CommonsSearch.new.search(query, limit: MAX_CANDIDATES)
      pixabay_key = ENV["PIXABAY_API_KEY"].presence
      if pixabay_key && results.size < MAX_CANDIDATES
        results += Media::PixabaySearch.new(api_key: pixabay_key).search(query, limit: MAX_CANDIDATES - results.size)
      end
      results.first(MAX_CANDIDATES)
    end
end
