module ProjectsHelper
  STATUS_STYLES = {
    "draft" => "bg-zinc-800 text-zinc-300",
    "script_ready" => "bg-amber-400/15 text-amber-300",
    "voice_ready" => "bg-sky-400/15 text-sky-300",
    "scenes_ready" => "bg-violet-400/15 text-violet-300",
    "media_ready" => "bg-fuchsia-400/15 text-fuchsia-300",
    "rendering" => "bg-purple-400/15 text-purple-300",
    "rendered" => "bg-emerald-400/15 text-emerald-300"
  }.freeze

  # Literal class names so Tailwind picks them up.
  THUMBNAIL_GRADIENTS = [
    "from-amber-900/60 to-zinc-900",
    "from-sky-900/60 to-zinc-900",
    "from-rose-900/60 to-zinc-900",
    "from-emerald-900/60 to-zinc-900",
    "from-violet-900/60 to-zinc-900"
  ].freeze

  WIZARD_STEPS = %w[Script Voice Scenes Music Render Publish].freeze

  def status_badge(project, id: nil)
    tag.span(project.status.humanize, id: id,
      class: "inline-flex items-center whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-medium #{STATUS_STYLES.fetch(project.status)}")
  end

  def thumbnail_gradient(project)
    THUMBNAIL_GRADIENTS[project.id % THUMBNAIL_GRADIENTS.size]
  end

  # Path for a wizard step, or nil when the step is not reachable yet.
  def wizard_step_path(project, step)
    case step
    when "Script" then project_path(project)
    when "Voice" then project_voice_path(project) if project.voice_available?
    when "Scenes" then project_scenes_path(project) if project.voice_track&.confirmed?
    end
  end

  def wizard_step_done?(project, step)
    case step
    when "Script" then project.latest_script.present?
    when "Voice" then project.voice_track&.confirmed? || false
    else false
    end
  end

  def reading_time_label(words)
    minutes = words / Project::WORDS_PER_MINUTE.to_f
    format("≈ %d:%02d", minutes.floor, ((minutes % 1) * 60).round)
  end

  def tone_options
    Project::TONES.map { |tone| [ tone.humanize, tone ] }
  end

  def target_length_options
    Project::TARGET_LENGTH_MINUTES.map { |minutes| [ "#{minutes} minutes", minutes ] }
  end
end
