module ScenesHelper
  SOURCE_BADGES = {
    "wikimedia_commons" => [ "Commons", "bg-sky-500/15 text-sky-300" ],
    "pixabay" => [ "Pixabay", "bg-emerald-500/15 text-emerald-300" ],
    "upload" => [ "Upload", "bg-zinc-700 text-zinc-200" ],
    "ai" => [ "AI", "bg-violet-500/15 text-violet-300" ]
  }.freeze

  CHECK_BADGES = {
    "verified" => [ "✓ Checked", "bg-emerald-500/15 text-emerald-300" ],
    "chosen" => [ "Your choice", "bg-zinc-700 text-zinc-200" ],
    "ai_suggested" => [ "AI image suggested", "bg-violet-500/15 text-violet-300" ],
    "unchecked" => [ "Not checked", "bg-amber-400/15 text-amber-300" ]
  }.freeze

  # Whether the scene's picture passed the AI check, was picked by the user, or still needs attention.
  def media_check_badge(scene)
    key = scene.media_check
    image = scene.selected_image
    key = "unchecked" if key.nil? && image && !image.stored_file?
    label, classes = CHECK_BADGES[key]
    tag.span(label, class: "rounded-md px-1.5 py-0.5 font-medium #{classes}", title: scene.media_note) if label
  end

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

  # A still to show for any candidate: the image itself, or a video's poster frame.
  def scene_image_src(image)
    return image.poster_url.presence || image.image_url if image.video?

    image.stored_file? ? rails_blob_path(image.file, disposition: "inline") : image.image_url
  end

  # The part of a source video the scene will use, as a media fragment for the preview player.
  def scene_video_preview_src(image, scene)
    start = image.clip_start_ms.to_i / 1000.0
    "#{image.image_url}#t=#{format("%.1f", start)},#{format("%.1f", start + scene.duration_ms / 1000.0)}"
  end

  def image_source_badge(image)
    label, classes = SOURCE_BADGES.fetch(image.provider, [ image.provider.humanize, "bg-zinc-700 text-zinc-200" ])
    label = "#{label} video" if image.video?
    tag.span(label, class: "rounded-md px-1.5 py-0.5 font-medium #{classes}")
  end

  def scene_image_counts(scenes)
    selected = scenes.map(&:selected_image)
    { free: selected.count { |image| image && !image.stored_file? && !image.video? },
      videos: selected.count { |image| image&.video? },
      uploaded: selected.count { |image| image&.upload? },
      ai: selected.count { |image| image&.ai? },
      missing: selected.count(&:nil?) }
  end

  def small_button_classes
    "#{secondary_button_classes} px-3 py-1.5 text-xs"
  end
end
