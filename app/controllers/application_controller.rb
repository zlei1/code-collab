class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :logged_in?

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    return if logged_in?
    redirect_to login_path, alert: "Please log in to continue."
  end

  def require_room_access!(room)
    return if room.users.exists?(id: current_user.id)
    redirect_to join_room_path(room.slug), alert: "Join the room to continue."
  end
end
