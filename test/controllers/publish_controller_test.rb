require "test_helper"

class PublishControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = project_with_approved_scenes(@user)
    attach_rendered_video(@project)
    sign_in @user
  end

  test "publishing needs a rendered video" do
    @project.update!(status: "media_ready")

    get project_publish_url(@project)

    assert_redirected_to project_render_url(@project)
  end

  test "shows the video, downloads, and the details form" do
    @project.update!(yt_title: "Why the Sea Rises", yt_tags: %w[tides moon], yt_category: "Education")

    get project_publish_url(@project)

    assert_response :success
    assert_select "video[controls]"
    assert_select "a", text: "Download MP4 · 1080p"
    assert_select "a", text: "Download thumbnail"
    assert_select "input[name='project[yt_title]'][value=?]", "Why the Sea Rises"
    assert_select "input[name='project[yt_tags]'][value=?]", "tides, moon"
    assert_select "textarea[data-clipboard-target=source]", text: /Why the Sea Rises/
  end

  test "saving details splits the tags" do
    patch project_publish_url(@project), params: { project: { yt_title: "New title", yt_description: "Desc",
                                                              yt_tags: "tides, moon ,, sea", yt_category: "Education" } }

    @project.reload
    assert_equal "New title", @project.yt_title
    assert_equal %w[tides moon sea], @project.yt_tags
  end

  test "an unknown category is refused" do
    patch project_publish_url(@project), params: { project: { yt_title: "t", yt_description: "", yt_tags: "", yt_category: "Lasers" } }

    assert_match "Yt category", flash[:alert]
  end

  test "writing details queues the job once" do
    assert_enqueued_with(job: GenerateMetadataJob) { post generate_project_publish_url(@project) }
    assert @project.reload.settings["metadata_generating"]

    assert_no_enqueued_jobs { post generate_project_publish_url(@project) }
  end

  test "the wizard marks Publish done once details exist" do
    @project.update!(yt_title: "Done")

    get project_publish_url(@project)

    assert_select "li[aria-current=step]", text: /Publish/
    assert_select "li", text: /Render/ do
      assert_select "svg"
    end
  end

  test "downloads SRT captions timed from the narration's parts" do
    @project.voice_track.update!(timings: [ { "text" => "Tides follow the moon.", "start_ms" => 0, "end_ms" => 2_000 } ])

    get captions_project_publish_url(@project)

    assert_response :success
    assert_equal "application/x-subrip", response.media_type
    assert_match(/attachment; filename="how-tides-work\.srt"/, response.headers["Content-Disposition"])
    assert_equal "1\n00:00:00,000 --> 00:00:02,000\nTides follow the moon.\n", response.body
  end

  test "says caption timing is approximate for narration made before part timings" do
    get project_publish_url(@project)

    assert_select "p", text: /caption timing is approximate/
  end
end
