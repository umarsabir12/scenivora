require "test_helper"

class ScenesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = @user.projects.create!(prompt: "How tides work", tone: "documentary", target_length_minutes: 4)
    @project.scripts.create!(body: "A narration about tides.", version: 1)
    @project.script_ready!
    sign_in @user
  end

  test "the placeholder Scenes page is reachable and marks Scenes as the current step" do
    get project_scenes_url(@project)

    assert_response :success
    assert_select "li[aria-current='step']", text: /Scenes/
    assert_select "h2", text: "Scenes are the next step"
  end

  test "Scenes is not reachable in the wizard until the voice is confirmed" do
    get project_url(@project)

    assert_select "a[href=?]", project_scenes_path(@project), count: 0
  end

  test "another user's project cannot open the Scenes page" do
    other = users(:two).projects.create!(prompt: "Someone else's video", tone: "casual", target_length_minutes: 3)

    get project_scenes_url(other)

    assert_response :not_found
  end
end
