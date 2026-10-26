module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    # Devise stores the signed-in user in the Warden session shared with the web app.
    def connect
      self.current_user = env["warden"]&.user || reject_unauthorized_connection
    end
  end
end
