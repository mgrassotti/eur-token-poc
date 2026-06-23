# frozen_string_literal: true

module Admin
  class DemoResetsController < ApplicationController
    before_action :require_login
    before_action :require_admin
    before_action :ensure_demo_reset_allowed

    def create
      DemoData::ResetService.call
      redirect_to root_path, notice: "Demo resettata"
    end

    private

    def ensure_demo_reset_allowed
      return unless Rails.env.production?

      redirect_to root_path, alert: "Reset demo non disponibile in produzione."
    end
  end
end
