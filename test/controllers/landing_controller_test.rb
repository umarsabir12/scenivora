require "test_helper"

class LandingControllerTest < ActionDispatch::IntegrationTest
  test "visitors see the landing page at the root" do
    get root_url

    assert_response :success
    assert_select "body.landing"
    assert_select "h1", text: /finished documentary/i
    assert_select "a[href='#{new_user_registration_path}']"
    assert_select "a[href='#{new_user_session_path}']"
  end

  test "the landing page lists every narrator the app has" do
    get root_url

    assert_select ".voice b", count: Ai::SpeechGenerator::VOICES.size
  end

  test "the landing page shows no costs" do
    get root_url

    assert_no_match(/\$\d/, response.body)
  end

  test "signed-in users get their projects at the root" do
    sign_in users(:one)

    get root_url

    assert_response :success
    assert_select "body.landing", count: 0
  end
end
