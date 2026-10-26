require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = @user.projects.create!(prompt: "Why octopuses have three hearts", tone: "casual", target_length_minutes: 3)
  end

  test "redirects anonymous visitors to sign in" do
    get projects_url

    assert_redirected_to new_user_session_url
  end

  test "index lists only the signed-in user's projects" do
    other = users(:two).projects.create!(prompt: "Secret project from another creator", tone: "casual", target_length_minutes: 3)
    sign_in @user

    get projects_url

    assert_response :success
    assert_select "h2", text: @project.title
    assert_select "h2", text: other.title, count: 0
  end

  test "new renders the project form" do
    sign_in @user

    get new_project_url

    assert_response :success
    assert_select "select[name='project[tone]']"
    assert_select "select[name='project[target_length_minutes]']"
  end

  test "create saves the project for the current user and opens it" do
    sign_in @user

    assert_difference -> { @user.projects.count }, 1 do
      post projects_url, params: {
        project: { prompt: "How lighthouses guided sailors", tone: "inspirational", target_length_minutes: 6 }
      }
    end

    project = Project.order(:created_at).last
    assert_redirected_to project_url(project)
    assert project.draft?
  end

  test "create with an invalid brief re-renders the form" do
    sign_in @user

    assert_no_difference -> { Project.count } do
      post projects_url, params: { project: { prompt: "", tone: "casual", target_length_minutes: 3 } }
    end

    assert_response :unprocessable_entity
  end

  test "show renders the wizard with only Script active" do
    sign_in @user

    get project_url(@project)

    assert_response :success
    assert_select "li[aria-current='step']", text: /Script/
    assert_select "li[aria-disabled='true']", count: 5
    assert_select "#script_panel"
  end

  test "show returns not found for another user's project" do
    other = users(:two).projects.create!(prompt: "Another creator's brief", tone: "casual", target_length_minutes: 3)
    sign_in @user

    get project_url(other)

    assert_response :not_found
  end
end
