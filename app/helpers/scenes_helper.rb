module ScenesHelper
  SOURCE_BADGES = {
    "wikimedia_commons" => [ "Commons", "bg-sky-500/15 text-sky-300" ],
    "pixabay" => [ "Pixabay", "bg-emerald-500/15 text-emerald-300" ],
    "upload" => [ "Upload", "bg-zinc-700 text-zinc-200" ],
    "ai" => [ "AI", "bg-violet-500/15 text-violet-300" ]
  }.freeze

  def format_timecode(milliseconds)
    total_seconds = milliseconds / 1000
    format("%d:%02d", total_seconds / 60, total_seconds % 60)
  end

  # Estimate for the planner call, before it runs. Scenes are about 10 seconds each.
  def planner_estimate_label(project, track)
    return "—" unless project.latest_script && track&.duration_ms

    scene_count = [ (track.duration_ms / 10_000.0).round, 1 ].max
    format("$%.4f", Ai::ScenePlanner.estimated_cost(project.latest_script.body, scene_count))
  end

  def scene_image_src(image)
    image.stored_file? ? rails_blob_path(image.file, disposition: "inline") : image.image_url
  end

  def image_source_badge(image)
    label, classes = SOURCE_BADGES.fetch(image.provider, [ image.provider.humanize, "bg-zinc-700 text-zinc-200" ])
    tag.span(label, class: "rounded-md px-1.5 py-0.5 font-medium #{classes}")
  end

  def scene_image_counts(scenes)
    selected = scenes.map(&:selected_image)
    { free: selected.count { |image| image && !image.stored_file? },
      uploaded: selected.count { |image| image&.upload? },
      ai: selected.count { |image| image&.ai? },
      missing: selected.count(&:nil?) }
  end

  def small_button_classes
    "#{secondary_button_classes} px-3 py-1.5 text-xs"
  end
end
