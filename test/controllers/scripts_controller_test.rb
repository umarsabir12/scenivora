require "test_helper"

class ScriptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = @user.projects.create!(prompt: "How deep-sea vents support life", tone: "documentary", target_length_minutes: 5)
    sign_in @user
  end

  test "create enqueues script generation and marks the project as generating" do
    assert_enqueued_with(job: GenerateScriptJob, args: [ @project ]) do
      post project_script_url(@project), as: :turbo_stream
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert @project.reload.script_generating?
  end

  test "create does not enqueue a second job while one is running" do
    @project.update!(settings: { "script_generating" => true })

    assert_no_enqueued_jobs only: GenerateScriptJob do
      post project_script_url(@project), as: :turbo_stream
    end
  end

  test "update autosaves the latest script body" do
    script = @project.scripts.create!(body: "Old narration", version: 1)

    patch project_script_url(@project), params: { script: { body: "Edited narration" } }, as: :json

    assert_response :success
    assert_equal "Edited narration", script.reload.body
  end

  test "update rejects an empty body without changing the script" do
    script = @project.scripts.create!(body: "Keep me", version: 1)

    patch project_script_url(@project), params: { script: { body: "" } }, as: :json

    assert_response :unprocessable_entity
    assert_equal "Keep me", script.reload.body
  end

  test "update returns not found when there is no script yet" do
    patch project_script_url(@project), params: { script: { body: "Orphan" } }, as: :json

    assert_response :not_found
  end

  test "scripts of another user's project cannot be touched" do
    other = users(:two).projects.create!(prompt: "Another creator's video", tone: "casual", target_length_minutes: 3)

    post project_script_url(other), as: :turbo_stream

    assert_response :not_found
    assert_not other.reload.script_generating?
  end
end
