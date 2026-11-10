require "test_helper"

class RendersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = project_with_approved_scenes(@user, status: "media_ready")
    sign_in @user
  end

  test "rendering needs the voice confirmed" do
    @project.update!(settings: { "storyboard" => true }, status: "scenes_ready")

    get project_render_url(@project)

    assert_redirected_to project_voice_url(@project)
  end

  test "music can be picked on the render page once the voice is confirmed" do
    @project.update!(status: "scenes_ready")

    get project_render_url(@project)

    assert_response :success
    assert_select "h2", text: "Background music"
    assert_select "form[action=?]", upload_project_music_path(@project)
  end

  test "rendering waits while a music track is still being prepared" do
    @project.create_music_track!(title: "Loading", source_url: "https://upload.wikimedia.org/a.ogg")

    assert_no_enqueued_jobs { post project_render_url(@project) }

    assert_redirected_to project_render_url(@project)
    assert_equal "Wait until the music track is ready, or remove it.", flash[:alert]
    assert @project.reload.media_ready?
  end

  test "shows a summary and the render button" do
    get project_render_url(@project)

    assert_response :success
    assert_select "dd", text: /Alloy/
    assert_select "dd", text: "2 scenes"
    assert_select "dd", text: "None"
    assert_select "form[action=?] input[type=submit][value=?]", project_render_path(@project), "Render video"
    assert_select "input[type=checkbox][name=captions][checked]"
  end

  test "starting a render marks the project and queues the job once" do
    assert_enqueued_with(job: RenderVideoJob) { post project_render_url(@project) }
    assert @project.reload.rendering?

    assert_no_enqueued_jobs { post project_render_url(@project) }
  end

  test "while rendering, progress shows instead of the button" do
    @project.update!(status: "rendering")

    get project_render_url(@project)

    assert_select "#render_progress[role=status]"
    assert_select "form[action=?]", project_render_path(@project), count: 0
  end

  test "while rendering, the chosen music shows but can't be changed" do
    ready_music_track(@project)
    @project.update!(status: "rendering")

    get project_render_url(@project)

    assert_select "#music-heading"
    assert_match "Calm piano", response.body
    assert_select "form[action=?]", project_music_path(@project), count: 0
    assert_select "form[action=?]", upload_project_music_path(@project), count: 0
  end

  test "the page has music, render and publish, in that order, with no music search" do
    get project_render_url(@project)

    headings = css_select("h2").map { |h| h.text.strip }
    assert_equal [ "Background music", "Render video", "Your video is ready" ], headings
    assert_select "input[name=q]", count: 0
    assert_select "#publish-heading ~ *", text: /Render the video first/
    assert_match "Push to YouTube: feature coming soon", response.body
  end

  test "a rendered video plays, with publish and re-render actions" do
    attach_rendered_video(@project)

    get project_render_url(@project)

    assert_select "video[controls]"
    assert_select "a", text: "Download MP4 · 1080p"
    assert_select "#details-heading", text: "YouTube details"
    assert_select "form[action=?] input[name=?]", project_publish_path(@project), "project[yt_title]"
    assert_select "a[href=?]", project_render_path(@project), text: "Re-render", count: 0
    assert_select "form[action=?] input[type=submit][value=?]", project_render_path(@project), "Re-render"
  end

  test "a render error is shown" do
    @project.update!(render_error: "ffmpeg failed: bad image")

    get project_render_url(@project)

    assert_select "[role=alert]", text: "ffmpeg failed: bad image"
  end

  test "the captions choice is saved when a render starts" do
    post project_render_url(@project), params: { captions: "0" }

    assert_equal false, @project.reload.settings["captions"]
    assert_not @project.captions_enabled?
  end

  test "saving YouTube details from the render page comes back to it" do
    attach_rendered_video(@project)

    patch project_publish_url(@project), params: { project: { yt_title: "Tides", yt_description: "", yt_tags: "", yt_category: "" } },
                                         headers: { "Referer" => project_render_url(@project) }

    assert_redirected_to project_render_url(@project)
    assert_equal "Tides", @project.reload.yt_title
  end

  test "once rendered, the music card is hidden until Change is clicked" do
    attach_rendered_video(@project)

    get project_render_url(@project)
    assert_select "#music-heading", count: 0
    assert_select "a[href=?]", project_render_path(@project, music: 1), text: "Change"

    get project_render_url(@project, music: 1)
    assert_select "#music-heading"
    assert_select "a", text: "Change", count: 0
  end

  test "the music card opened with Change has Done to hide it again" do
    attach_rendered_video(@project)

    get project_render_url(@project, music: 1)

    assert_select "a[href=?]", project_render_path(@project), text: "Done"
  end

  test "during a re-render the current video and its details stay on the page" do
    attach_rendered_video(@project)
    @project.update!(status: "rendering")

    get project_render_url(@project)

    assert_select "video[controls]"
    assert_select "[role=status]", text: /Re-rendering/
    assert_select "form[action=?] input[name=?]", project_publish_path(@project), "project[yt_title]"
  end
end
