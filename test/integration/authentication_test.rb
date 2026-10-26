require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    ActionMailer::Base.deliveries.clear
  end

  test "signs in with the sign-in form and reaches the dashboard" do
    post user_session_url, params: { user: { email: @user.email, password: "password" } }

    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
  end

  test "a wrong password stays on the sign-in page with an error" do
    post user_session_url, params: { user: { email: @user.email, password: "wrong-password" } }

    assert_response :unprocessable_content
    assert_select "p[role='status']", text: /invalid email or password/i
  end

  test "signing out ends the session" do
    sign_in @user

    delete destroy_user_session_url
    get root_url

    assert_redirected_to new_user_session_url
  end

  test "password reset emails a link that sets a new password" do
    post user_password_url, params: { user: { email: @user.email } }

    assert_equal 1, ActionMailer::Base.deliveries.size
    token = ActionMailer::Base.deliveries.last.body.encoded[/reset_password_token=([^"&\s<]+)/, 1]
    assert token.present?

    put user_password_url, params: {
      user: { reset_password_token: token, password: "brand-new-pass", password_confirmation: "brand-new-pass" }
    }

    assert @user.reload.valid_password?("brand-new-pass")
  end
end
