# "Create video": researches and writes the script, lays it out as storyboard scenes, finds and
# checks a picture for each, and starts AI images (up to MAX_AI_IMAGES, paid in credits) where no
# real picture fits. The user then edits the storyboard before the voice is made. Progress is kept
# in settings["production"] and shown on the storyboard page.
class ProduceVideoJob < ApplicationJob
  queue_as :default

  MAX_AI_IMAGES = 8
  FAILED = "Creating the video failed. Try again.".freeze

  def perform(project)
    advance(project, "writing")
    ScriptWriter.new.write(project)
    build_storyboard(project)

    advance(project, "pictures")
    FindSceneImagesJob.perform_now(project)

    advance(project, "ai_images")
    note = [ story_note(project), start_ai_images(project) ].compact.join(" ").presence

    project.update!(status: :script_ready, settings: project.settings.merge("production" => { "step" => "done", "note" => note }.compact))
  rescue StandardError => e
    Rails.logger.error("Creating the video failed for project #{project.id}: #{e.class}: #{e.message}")
    project.update!(settings: project.settings.merge("production" => { "step" => "failed", "error" => FAILED }))
  ensure
    Turbo::StreamsChannel.broadcast_refresh_to([ project, :scenes ])
  end

  private
    def advance(project, step)
      project.update!(settings: project.settings.merge("production" => { "step" => step }))
      Turbo::StreamsChannel.broadcast_refresh_to([ project, :scenes ])
    end

    # The script's paragraphs become the scenes, timed from their words until the voice exists.
    # A new storyboard needs a new voice, so the old one is no longer confirmed.
    def build_storyboard(project)
      Scene.transaction do
        project.scenes.destroy_all
        StoryboardScenes.new(project.latest_script.body).scenes.each do |scene|
          project.scenes.create!(position: scene.position, text: scene.text, start_ms: scene.start_ms,
                                 duration_ms: scene.duration_ms, search_query: Scene.query_for(scene.text))
        end
        project.voice_track&.update!(confirmed_at: nil)
        project.update!(settings: project.settings.merge("storyboard" => true).except("scene_key"))
      end
    end

    # Tells the user when the research found no reliable source for the brief's own story, so they
    # know the script tells it as a story rather than as fact.
    def story_note(project)
      check = project.settings.dig("research", "story_check")
      return unless check.is_a?(Hash) && check["status"] == "unverified"

      "The story in your brief couldn't be verified, so the script tells it as a story, not as fact. #{check["note"]}".strip
    end

    # AI images for the scenes no real picture fits, hook scenes first, while the user's credits last.
    # Returns a note for the user when some were left for later.
    def start_ai_images(project)
      waiting = project.scenes.reload.select(&:ai_suggested?)
      started = 0
      waiting.first(MAX_AI_IMAGES).each do |scene|
        started += 1 if scene.start_ai_image!(project.user, scene.suggested_ai_prompt)
      rescue User::InsufficientCredits
        break
      end

      left = waiting.size - started
      return if left.zero?

      verb = left == 1 ? "still needs" : "still need"
      "#{ActionController::Base.helpers.pluralize(left, "scene")} #{verb} an AI image#{" (not enough credits)" if started < [ waiting.size, MAX_AI_IMAGES ].min}."
    end
end
