# Writes the narration script (see ScriptWriter) and updates the script panel.
class GenerateScriptJob < ApplicationJob
  queue_as :default

  def perform(project)
    error = nil
    generate(project)
  rescue Ai::TextGenerator::Error => e
    Rails.logger.error("Script generation failed for project #{project.id}: #{e.message}")
    error = "Script generation failed. Please try again."
  ensure
    # Always clear the generating state so the page never gets stuck on "Generating…".
    finish_generation(project, error: error)
  end

  private
    def generate(project)
      ScriptWriter.new.write(project)
      project.script_ready!
    end

    def finish_generation(project, error: nil)
      project.update!(settings: project.settings.except("script_generating"))
      Turbo::StreamsChannel.broadcast_replace_to(
        project,
        target: "project_status",
        partial: "projects/status_badge",
        locals: { project: project }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        project,
        target: "script_panel",
        partial: "projects/script_panel",
        locals: { project: project, error: error }
      )
    end
end
