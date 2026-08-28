# frozen_string_literal: true

module Admin
  class BudgetsController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def simulate_sepa_out
      budget = Budget.find(params[:id])
      Funding::SimulateSepaOut.call(budget: budget)
      redirect_to root_path, notice: t("flash.admin.sepa_out.created")
    rescue Funding::SimulateSepaOut::Error => e
      redirect_to root_path, alert: e.message
    end
  end
end
