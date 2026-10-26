require "test_helper"

class UsersRegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "sign-up page is public" do
    get new_user_registration_url

    assert_response :success
  end

  test "signing up creates an account, signs the user in, and opens the dashboard" do
    assert_difference -> { User.count }, 1 do
      post user_registration_url, params: {
        user: { email: "new.creator@example.com", password: "password123", password_confirmation: "password123" }
      }
    end

    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
  end

  test "invalid sign-up re-renders the form with errors" do
    assert_no_difference -> { User.count } do
      post user_registration_url, params: {
        user: { email: "bad", password: "short", password_confirmation: "mismatch" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "signed-in dashboard shows the credit balance placeholder" do
    sign_in users(:one)

    get root_url

    assert_response :success
    assert_select "[data-testid='credits-balance']", text: "0"
  end
end
