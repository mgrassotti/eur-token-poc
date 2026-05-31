# frozen_string_literal: true

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  helper_method :current_user, :logged_in?, :admin?

  private

  def admin?
    current_user&.admin?
  end

  def require_admin
    return if admin?

    redirect_to root_path, alert: "Solo l'admin può eseguire questa operazione."
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    return if logged_in?

    redirect_to login_path, alert: "Please log in to continue."
  end
end
