# The public home page for signed-out visitors. Signed-in users get their projects at "/" instead
# (see the authenticated root in config/routes.rb).
class LandingController < ApplicationController
  skip_before_action :authenticate_user!
  layout "landing"

  def show
  end
end
