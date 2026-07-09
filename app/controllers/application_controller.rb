# frozen_string_literal: true

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  around_action :switch_locale

  helper_method :current_user, :logged_in?, :admin?, :available_locales, :locale_switch_url

  private

  def switch_locale(&action)
    locale = requested_locale || I18n.default_locale
    I18n.with_locale(locale, &action)
  end

  def requested_locale
    locale = params[:locale].presence || session[:locale]
    locale = locale.to_sym if locale.present?
    locale = nil unless available_locales.include?(locale)
    session[:locale] = locale&.to_s if locale.present?
    locale
  end

  def default_url_options
    locale = I18n.locale == I18n.default_locale ? nil : I18n.locale
    locale ? { locale: locale } : {}
  end

  def available_locales
    I18n.available_locales
  end

  def locale_switch_url(locale)
    path_params = request.path_parameters.symbolize_keys.except(:locale)
    query_params = request.query_parameters.symbolize_keys.except(:locale)
    path_params[:action] = :new if !request.get? && path_params[:action] == "create"

    url_for(path_params.merge(query_params).merge(locale: locale))
  end

  def admin?
    current_user&.admin?
  end

  def require_admin
    return if admin?

    redirect_to root_path, alert: t("flash.authorization.admin_only")
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    return if logged_in?

    redirect_to login_path, alert: t("flash.authorization.login_required")
  end
end
