require "test_helper"

class ScenesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = @user.projects.create!(prompt: "How tides work", tone: "documentary", target_length_minutes: 4)
    @project.scripts.create!(body: "Tides follow the moon.", version: 1)
    @project.script_ready!
    sign_in @user
  end

  def confirmed_track
    track = @project.create_voice_track!(kind: "voice", voice_name: "alloy", speed: 1.0, duration_ms: 60_000,
      script_digest: @project.latest_script.digest, confirmed_at: Time.current)
    track.file.attach(io: StringIO.new("mp3"), filename: "n.mp3", content_type: "audio/mpeg")
    track.update!(status: "ready")
    track
  end

  test "before the voice is confirmed the create button is not shown" do
    get project_scenes_url(@project)

    assert_response :success
    assert_select "p", text: /Confirm the narration voice first/
    assert_select "form[action=?]", project_scenes_path(@project), count: 0
  end

  test "after confirmation the button says Create scene and shows its estimated cost" do
    confirmed_track

    get project_scenes_url(@project)

    assert_select "form[action=?] button", project_scenes_path(@project), text: /\ACreate scene · est\. \$\d+\.\d{4}\z/
  end

  test "create enqueues the image job and marks the project as searching" do
    confirmed_track

    assert_enqueued_with(job: FindSceneImagesJob, args: [ @project ]) do
      post project_scenes_url(@project)
    end

    assert_redirected_to project_scenes_url(@project)
    assert @project.reload.settings["scenes_searching"]
  end

  test "a second create while searching does not enqueue another job" do
    confirmed_track
    @project.update!(settings: { "scenes_searching" => true })

    assert_no_enqueued_jobs(only: FindSceneImagesJob) do
      post project_scenes_url(@project)
    end
  end

  test "create is refused until the voice is confirmed" do
    assert_no_enqueued_jobs do
      post project_scenes_url(@project)
    end

    assert_redirected_to project_voice_url(@project)
  end

  test "the page lists scenes with the credit, license, source and a note for scenes without images" do
    confirmed_track
    scene = @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 60_000)
    scene.images.create!(provider: "wikimedia_commons", image_url: "https://img.example/a.jpg",
      page_url: "https://src.example/a", credit: "Jane", license: "CC BY 4.0", selected: true)

    get project_scenes_url(@project)

    assert_select "li", text: /Tides follow the moon/
    assert_select "span", text: "Commons"
    assert_select "span", text: "CC BY 4.0"
    assert_select "a[href=?]", "https://src.example/a", text: "Jane"

    scene.images.destroy_all
    get project_scenes_url(@project)
    assert_select "p", text: /No free image found/
  end

  test "another user's project cannot open or create scenes" do
    other = users(:two).projects.create!(prompt: "Someone else's video", tone: "casual", target_length_minutes: 3)

    get project_scenes_url(other)
    assert_response :not_found
  end

  test "another user's project cannot start scene creation" do
    other = users(:two).projects.create!(prompt: "Someone else's video", tone: "casual", target_length_minutes: 3)

    assert_no_enqueued_jobs do
      post project_scenes_url(other)
    end
    assert_response :not_found
  end

  test "a scene with a selected image shows its thumbnail" do
    confirmed_track
    scene = @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 60_000)
    scene.images.create!(provider: "wikimedia_commons", image_url: "https://upload.wikimedia.org/a.jpg",
      page_url: "https://commons.wikimedia.org/wiki/File:A.jpg", credit: "Jane", license: "CC BY 4.0", selected: true)

    get project_scenes_url(@project)

    assert_select "img[src=?][alt=?]", "https://upload.wikimedia.org/a.jpg", "Image for scene 1"
  end

  test "the create button is hidden once scenes exist" do
    confirmed_track
    @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 60_000)

    get project_scenes_url(@project)

    assert_select "form[action=?]", project_scenes_path(@project), count: 0
  end

  test "while images are being found, the page shows progress instead of the button" do
    confirmed_track
    @project.update!(settings: @project.settings.merge("scenes_searching" => true))

    get project_scenes_url(@project)

    assert_select "p[role=status]", text: /Finding images\.\.\./
    assert_select "form[action=?]", project_scenes_path(@project), count: 0
  end

  test "after a failed planning run, a Retry button replaces the hidden create button" do
    confirmed_track
    @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 60_000,
      search_error: FindSceneImagesJob::PLANNING_FAILED)

    get project_scenes_url(@project)

    assert_select "form[action=?] button", project_scenes_path(@project), text: /\ARetry planning · est\./
  end

  test "retry re-runs the job for scenes that already exist" do
    confirmed_track
    @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 60_000,
      search_error: FindSceneImagesJob::PLANNING_FAILED)

    assert_enqueued_with(job: FindSceneImagesJob) do
      post project_scenes_url(@project)
    end
  end

  test "the swap panel shows the chosen scene's candidates, with the selected one marked" do
    confirmed_track
    first = @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 30_000)
    second = @project.scenes.create!(position: 2, text: "The sea rises twice a day.", start_ms: 30_000, duration_ms: 30_000)
    second.images.create!(provider: "wikimedia_commons", image_url: "https://img.example/b.jpg", credit: "Ann", license: "CC0", selected: true)
    second.images.create!(provider: "wikimedia_commons", image_url: "https://img.example/c.jpg", credit: "Bo", license: "CC0")

    get project_scenes_url(@project, scene: second.id)

    assert_select "#swap h2", text: "Swap image · Scene 2"
    assert_select "#swap button[aria-pressed=true] img[src=?]", "https://img.example/b.jpg"
    assert_select "#swap button[aria-pressed=false] img[src=?]", "https://img.example/c.jpg"
    assert_select "li#scene_#{second.id}[aria-current=true]"
    assert_select "li#scene_#{first.id}[aria-current=false]"
  end

  test "approve is disabled while a scene has no image" do
    confirmed_track
    @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 60_000)

    get project_scenes_url(@project)

    assert_select "button[disabled]", text: "Approve scenes & continue"
    assert_select "p", text: "1 scene still needs an image."
  end

  test "approving with a scene missing an image is refused" do
    confirmed_track
    scene = @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 60_000)

    post approve_project_scenes_url(@project)

    assert_redirected_to project_scenes_url(@project, scene: scene.id, anchor: "swap")
    assert_not @project.reload.scenes_ready?
  end

  test "approving when every scene has an image moves the project to music" do
    confirmed_track
    scene = @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 60_000)
    scene.images.create!(provider: "wikimedia_commons", image_url: "https://img.example/a.jpg", credit: "Jane", license: "CC0", selected: true)

    post approve_project_scenes_url(@project)

    assert_redirected_to project_music_url(@project)
    assert @project.reload.scenes_ready?

    follow_redirect!
    assert_select "li[aria-current='step']", text: /Music/
    get project_voice_url(@project)
    assert_response :success
  end

  test "the AI generate tab shows the cost and balance, and is disabled without enough credits" do
    confirmed_track
    scene = @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 60_000)

    get project_scenes_url(@project, scene: scene.id, source: "ai")

    assert_select "#swap a[aria-current=page]", text: "AI generate"
    assert_select "#swap textarea[name=prompt]", text: /Tides follow the moon/
    assert_select "#swap button[disabled]", text: "Generate · #{CreditPricing.ai_image} credits"

    @user.grant_credits!(CreditPricing.ai_image, reason: "manual_grant")
    get project_scenes_url(@project, scene: scene.id, source: "ai")
    assert_select "#swap input[type=submit][value=?]", "Generate · #{CreditPricing.ai_image} credits"
  end

  test "the AI tab shows progress while generating and the refund note after a failure" do
    confirmed_track
    scene = @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 60_000,
                                    ai_status: "generating")

    get project_scenes_url(@project, scene: scene.id, source: "ai")
    assert_select "#swap p[role=status]", text: /Generating an image/

    scene.update!(ai_status: "failed", ai_error: "Image generation failed: busy")
    get project_scenes_url(@project, scene: scene.id, source: "ai")
    assert_select "#swap p[role=alert]", text: /busy.*Your credits were refunded/
  end

  test "a scene card shows a loader over its thumbnail while its AI image is generating" do
    confirmed_track
    scene = @project.scenes.create!(position: 1, text: "Tides follow the moon.", start_ms: 0, duration_ms: 60_000,
                                    ai_status: "generating")

    get project_scenes_url(@project)
    assert_select "li#scene_#{scene.id} [role=status][aria-label=?]", "Generating an AI image for scene 1"

    scene.update!(ai_status: nil)
    get project_scenes_url(@project)
    assert_select "li#scene_#{scene.id} [role=status]", count: 0
  end
end
