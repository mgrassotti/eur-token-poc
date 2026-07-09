# frozen_string_literal: true

module Admin
  class DemoResetsController < ApplicationController
    before_action :require_login
    before_action :require_admin
    before_action :ensure_demo_reset_allowed

    def create
      DemoData::ResetService.call
      redirect_to root_path, notice: t("flash.admin.demo_reset.done")
    end

    private

    def ensure_demo_reset_allowed
      return unless Rails.env.production?

      redirect_to root_path, alert: t("flash.admin.demo_reset.unavailable_in_production")
    end
  end
end
