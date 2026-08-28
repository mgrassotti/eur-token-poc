# frozen_string_literal: true

module Admin
  class FundingRequestsController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def simulate_sepa_in
      request = FundingRequest.find(params[:id])
      Funding::SimulateSepaIn.call(request: request)
      redirect_to root_path, notice: t("flash.admin.sepa_in.created", amount: BtcConversion.format_eur(request.amount_eur_cents))
    rescue Funding::SimulateSepaIn::Error => e
      redirect_to root_path, alert: e.message
    end

    def simulate_investor_deposit
      request = FundingRequest.find(params[:id])
      Funding::SimulateInvestorDeposit.call(request: request)
      redirect_to root_path, notice: t("flash.admin.investor_deposit.created")
    rescue Funding::SimulateInvestorDeposit::Error => e
      redirect_to root_path, alert: e.message
    end
  end
end
