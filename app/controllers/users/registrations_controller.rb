class Users::RegistrationsController < Devise::RegistrationsController
  rate_limit to: 5, within: 10.minutes, only: :create,
    with: -> { redirect_to new_user_registration_path, alert: "Too many sign-up attempts. Try again later." }
end
