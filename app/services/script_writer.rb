# Writes a project's narration script as a list of scenes: short paragraphs, each one shot of the
# video. When the Director is on, the topic is researched on Wikipedia first (or the stored
# research is reused while the brief is unchanged) and a strong model writes from those facts,
# naming things that can be shown. If research or that model fails, the cheap model writes from
# the brief alone. Saves the next Script version and records its cost.
class ScriptWriter
  SYSTEM_PROMPT = <<~PROMPT.freeze
    You write narration scripts for faceless YouTube videos. The script will be read aloud by a synthetic voice, so write for the ear: short, clear sentences and natural rhythm.

    Structure:
    - Hook: the first 15 seconds (roughly the first 35 words) must grab attention with a surprising fact, a sharp question, or a bold claim.
    - Story: build a clear narrative with setup, rising tension, a turning point about halfway through, then payoff and a memorable closing takeaway.
    - Length: about 150 words per minute of the requested target length.

    Output rules:
    - Plain narration text only, in short paragraphs separated by blank lines. Each paragraph is one
      shot of the video, shown with one picture: one or two sentences, about 15 to 35 words, about
      one subject.
    - No titles, headings, scene directions, camera notes, sound cues, speaker labels, timestamps, or markdown.
    - Match the requested tone.
  PROMPT

  RESEARCH_RULES = <<~PROMPT.freeze

    Research rules:
    - Tell the story the brief asks for. Most of the script stays on that story; background and
      what came after get a sentence or two, not paragraphs of their own.
    - Write between the minimum and maximum word counts given. Do not exceed the maximum.
    - Use only the facts in the research below. When the brief disagrees with the research (a date,
      a detail), follow the research. Attribute uncertain items ("according to ...") or leave them out.
    - Every paragraph names at least one concrete visual subject from the research (a person, place,
      ship, building, object, document or event, with the year when it matters), so every shot can
      be shown.
    - No abstract moral or "legacy" paragraphs, no "As we reflect", no "stay to the end", no calls to
      like or subscribe. End on a concrete fact, place or image rather than a moral.
    - Follow the creator's instructions when they are given.
  PROMPT

  # A script longer than the prompt's maximum (10% over its target) is shortened once.
  MAX_LENGTH_RATIO = 1.1
  SHORTEN_PROMPT = <<~PROMPT.freeze
    Shorten this narration script to the word count given. Keep the hook, the story's order, the
    facts and the names of the people, places and things it shows; cut repetition, background and
    side stories first. Keep the short paragraphs (one or two sentences each) separated by blank
    lines. Return only the shortened script.
  PROMPT

  def write(project)
    research = research_for(project)
    result = (research && write_from_research(project, research)) || write_from_brief(project)

    project.transaction do
      project.api_usages.create!(provider: result.provider, operation: "script", units: result.total_tokens,
                                 cost_usd: result.cost_usd)
      project.scripts.create!(body: result.text, version: project.next_script_version)
    end
  end

  private
    def write_from_brief(project)
      Ai::TextGenerator.new.call(system_prompt: SYSTEM_PROMPT, user_prompt: user_prompt_for(project))
    end

    def write_from_research(project, research)
      writer = Ai::ResearchGenerator.new(model: script_model)
      results = [ writer.call(instructions: SYSTEM_PROMPT + RESEARCH_RULES, input: research_prompt_for(project, research),
                              effort: "low") ]
      if results.first.text.split.size > project.target_word_count * MAX_LENGTH_RATIO
        results << writer.call(instructions: SHORTEN_PROMPT, effort: "low",
                               input: "Word count: about #{project.target_word_count}\n\n#{results.first.text}")
      end
      Ai::TextGenerator::Result.new(text: results.last.text, provider: results.last.provider, model: results.last.model,
                                    total_tokens: results.sum(&:total_tokens), cost_usd: results.sum(&:cost_usd))
    rescue Ai::Error => e
      Rails.logger.warn("Script from research failed for project #{project.id}: #{e.message}; writing from the brief")
      nil
    end

    def script_model
      ENV["OPENAI_SCRIPT_MODEL"].presence || ENV.fetch("OPENAI_DIRECTOR_MODEL", Ai::ResearchGenerator::DEFAULT_MODEL)
    end

    # The stored research while the brief is unchanged, else new research (saved on the project).
    # nil when the Director is off or research failed.
    def research_for(project)
      return unless Ai::Director.enabled?

      key = Ai::Researcher.key_for(project)
      stored = project.settings["research"]
      return stored if stored.is_a?(Hash) && stored["key"] == key

      research = Ai::Researcher.new.call(project)
      project.api_usages.create!(provider: Ai::ResearchGenerator::PROVIDER, operation: "research",
                                 units: research.total_tokens, cost_usd: research.cost_usd)
      if research.dropped_articles.any?
        Rails.logger.info("Research named articles that don't exist for project #{project.id}: #{research.dropped_articles.inspect}")
      end
      project.update!(settings: project.settings.merge("research" => research.to_settings(key)))
      project.settings["research"]
    rescue Ai::Error => e
      Rails.logger.warn("Research failed for project #{project.id}: #{e.message}; writing the script from the brief")
      nil
    end

    def user_prompt_for(project)
      lines = [ "Brief: #{project.prompt}", "Tone: #{project.tone}",
                "Target length: #{project.target_length_minutes} minutes (about #{project.target_word_count} words)" ]
      lines << "Category: #{project.category}. #{Project::CATEGORIES[project.category]}" if project.category.present?
      lines << "The creator's instructions: #{project.instructions}" if project.instructions.present?
      lines.join("\n")
    end

    def research_prompt_for(project, research)
      subjects = Array(research["visual_subjects"]).map do |subject|
        "- #{subject["name"]} (#{[ subject["kind"], subject["year"] ].compact.join(", ")})"
      end
      words = project.target_word_count
      lines = [ user_prompt_for(project), "Word count: between #{(words * 0.9).round} and #{(words * 1.1).round} words." ]
      lines << "\nResearch facts:\n#{Array(research["facts"]).map { |fact| "- #{fact}" }.join("\n")}"
      lines << "\nVisual subjects:\n#{subjects.join("\n")}"
      lines << "\nUncertain (attribute or leave out):\n#{research["uncertain"].map { |item| "- #{item}" }.join("\n")}" if Array(research["uncertain"]).any?
      lines.join("\n")
    end
end
