require "test_helper"

class RendersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = project_with_approved_scenes(@user, status: "media_ready")
    sign_in @user
  end

  test "rendering needs the music step to be finished" do
    @project.update!(status: "scenes_ready")

    get project_render_url(@project)

    assert_redirected_to project_music_url(@project)
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

  test "a rendered video plays, with publish and re-render actions" do
    attach_rendered_video(@project)

    get project_render_url(@project)

    assert_select "video[controls]"
    assert_select "a[href=?]", project_publish_path(@project), text: "Continue to publish"
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
end
