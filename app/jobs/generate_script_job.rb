class GenerateScriptJob < ApplicationJob
  queue_as :default

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You write narration scripts for faceless YouTube videos. The script will be read aloud by a synthetic voice, so write for the ear: short, clear sentences and natural rhythm.

    Structure:
    - Hook: the first 15 seconds (roughly the first 35 words) must grab attention with a surprising fact, a sharp question, or a bold claim.
    - Story: build a clear narrative with setup, rising tension, a turning point about halfway through, then payoff and a memorable closing takeaway.
    - Length: about 150 words per minute of the requested target length.

    Output rules:
    - Plain narration text only, split into paragraphs with blank lines.
    - No titles, headings, scene directions, camera notes, sound cues, speaker labels, timestamps, or markdown.
    - Match the requested tone.
  PROMPT

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
      result = Ai::TextGenerator.new.call(
        system_prompt: SYSTEM_PROMPT,
        user_prompt: user_prompt_for(project)
      )

      project.transaction do
        project.scripts.create!(body: result.text, version: project.next_script_version)
        project.api_usages.create!(
          provider: result.provider,
          operation: "script",
          units: result.total_tokens,
          cost_usd: result.cost_usd
        )
        project.script_ready!
      end
    end

    def user_prompt_for(project)
      <<~PROMPT
        Brief: #{project.prompt}
        Tone: #{project.tone}
        Target length: #{project.target_length_minutes} minutes (about #{project.target_word_count} words)
      PROMPT
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
