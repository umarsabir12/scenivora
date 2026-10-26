# Review actions for one scene's image: pick a candidate, search Commons, upload, or remove.
class SceneImagesController < ApplicationController
  SEARCH_LIMIT = 6

  before_action :set_scene

  # Uploads the user's own image. It becomes the scene's selected image.
  def create
    image = @scene.images.build(provider: SceneImage::UPLOAD_PROVIDER, credit: "Your upload", license: "Provided by you")
    image.file.attach(params.require(:file))

    if image.save
      image.select!
      back_to_scene notice: "Image uploaded for scene #{@scene.position}."
    else
      back_to_scene alert: image.errors.full_messages.to_sentence
    end
  end

  def select
    @scene.images.find(params[:id]).select!
    back_to_scene
  end

  # Free search on Wikimedia Commons. Replaces the unpicked candidates; keeps the selected image and uploads.
  def search
    query = params[:query].to_s.strip
    return back_to_scene(alert: "Enter something to search for.") if query.empty?

    results = Media::CommonsSearch.new.search(query, limit: SEARCH_LIMIT)
    replace_candidates(results)
    @scene.update!(search_query: query, search_error: nil)
    back_to_scene(notice: (%(No free images found for "#{query}".) if results.empty?))
  rescue Media::Error => e
    Rails.logger.warn("Commons search failed for scene #{@scene.id}: #{e.message}")
    back_to_scene alert: "Image search failed. Try again later."
  end

  MAX_PROMPT_LENGTH = 1_000

  # Charges credits, then generates an AI image in the background. The job refunds on failure.
  def generate
    prompt = params[:prompt].to_s.strip
    return back_to_scene(alert: "Describe the image you want.", source: "ai") if prompt.empty?
    return back_to_scene(alert: "Keep the description under #{MAX_PROMPT_LENGTH} characters.", source: "ai") if prompt.length > MAX_PROMPT_LENGTH
    return back_to_scene(alert: "AI images are turned off for this scene because it shows a real person. Search or upload instead.", source: "ai") unless @scene.ai_allowed?

    cost = CreditPricing.ai_image
    started = Scene.transaction do
      @scene.lock!
      next false if @scene.ai_generating?

      current_user.charge_credits!(cost, reason: "ai_image", project: @scene.project)
      @scene.update!(ai_status: "generating", ai_error: nil)
      true
    end
    return back_to_scene(notice: "An image is already being generated for this scene.", source: "ai") unless started

    GenerateSceneImageJob.perform_later(@scene, prompt, cost)
    back_to_scene(notice: "Generating an AI image. #{helpers.pluralize(cost, "credit")} charged.", source: "ai")
  rescue User::InsufficientCredits
    back_to_scene alert: "You need #{helpers.pluralize(cost, "credit")} to generate an image. You have #{current_user.reload.credits_balance}.", source: "ai"
  end

  # Leaves the scene without a selected image. Its candidates stay available in the swap panel.
  def clear
    @scene.images.update_all(selected: false)
    back_to_scene notice: "Image removed from scene #{@scene.position}."
  end

  private
    def set_scene
      @scene = Scene.joins(:project).where(projects: { user_id: current_user.id }).find(params[:scene_id])
    end

    def replace_candidates(results)
      SceneImage.transaction do
        @scene.images.where(selected: false).where.not(provider: SceneImage::UPLOAD_PROVIDER).destroy_all
        known_urls = @scene.images.pluck(:image_url)
        results.reject { |result| known_urls.include?(result.image_url) }.each do |result|
          @scene.images.create!(provider: result.provider, image_url: result.image_url, page_url: result.page_url,
                                credit: result.credit, license: result.license)
        end
      end
    end

    def back_to_scene(notice: nil, alert: nil, source: nil)
      redirect_to project_scenes_path(@scene.project_id, scene: @scene.id, source: source, anchor: "swap"),
        notice: notice, alert: alert
    end
end
