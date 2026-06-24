# frozen_string_literal: true

module Dev
  class UserSwitchesController < ApplicationController
    before_action :ensure_development

    def create
      user = User.find(params[:user_id])
      session[:user_id] = user.id
      redirect_to root_path
    end

    private

    def ensure_development
      head :not_found unless Rails.env.development? || Rails.env.test?
    end
  end
end
