class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Devise's own pages (sign in, sign up, reset password) must stay reachable while signed out.
  before_action :authenticate_user!, unless: :devise_controller?

  layout :layout_by_context

  private
    def layout_by_context
      devise_controller? ? "auth" : "application"
    end
end
