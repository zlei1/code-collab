module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :client_id, :current_user

    def connect
      self.client_id = SecureRandom.uuid
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      user_id = request.session[:user_id]
      user = user_id && User.find_by(id: user_id)
      return user if user

      reject_unauthorized_connection
    end
  end
end
