# Builds a project that has reached the scenes-approved stage, for tests of the later steps.
module ProductionSteps
  def project_with_approved_scenes(user = users(:one), status: "scenes_ready")
    project = user.projects.create!(prompt: "How tides work", tone: "documentary", target_length_minutes: 3,
                                    settings: { "ai_voice" => true })
    project.scripts.create!(body: "Tides follow the moon. The sea rises twice a day.", version: 1)
    voice = project.create_voice_track!(kind: "voice", voice_name: "alloy", speed: 1.0, duration_ms: 20_000,
                                        script_digest: project.latest_script.digest, confirmed_at: Time.current)
    voice.file.attach(io: StringIO.new("narration"), filename: "narration.mp3", content_type: "audio/mpeg")
    voice.update!(status: "ready")

    first = project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 10_000)
    first.images.create!(provider: "wikimedia_commons", image_url: "https://upload.wikimedia.org/a.jpg",
                         page_url: "https://commons.wikimedia.org/wiki/File:A.jpg", credit: "Jane", license: "CC BY 4.0", selected: true)
    second = project.scenes.create!(position: 2, text: "The sea rises twice a day.", start_ms: 10_000, duration_ms: 10_000)
    upload = second.images.build(provider: "upload", credit: "Your upload", license: "Provided by you", selected: true)
    upload.file.attach(io: StringIO.new("\x89PNG".b), filename: "mine.png", content_type: "image/png")
    upload.save!

    project.update!(status: status)
    project
  end

  def ready_music_track(project, volume: 18)
    track = project.build_music_track(title: "Calm piano", credit: "Kim", license: "CC BY 4.0", volume: volume,
                                      source_url: "https://upload.wikimedia.org/calm.ogg",
                                      page_url: "https://commons.wikimedia.org/wiki/File:Calm.ogg", duration_ms: 90_000)
    track.file.attach(io: File.open(Rails.root.join("test/fixtures/files/tone.mp3")), filename: "calm.mp3", content_type: "audio/mpeg")
    track.status = "ready"
    track.save!
    track
  end

  def attach_rendered_video(project)
    project.video.attach(io: StringIO.new("mp4"), filename: "video.mp4", content_type: "video/mp4")
    project.thumbnail.attach(io: StringIO.new("jpg"), filename: "thumb.jpg", content_type: "image/jpeg")
    project.update!(status: "rendered")
  end
end
