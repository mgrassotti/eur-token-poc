# frozen_string_literal: true

class InvestorCollateralDepositsController < ApplicationController
  before_action :require_login
  before_action :set_budget

  def create
    rate = MarketRate.current.btc_eur_per_btc
    amount_cents = (params[:amount_eur].to_d * 100).round
    amount_sats = BtcConversion.eur_cents_to_sats(amount_cents, rate)

    Budgets::InvestorCollateralTopUpService.call(
      budget: @budget,
      investor: current_user,
      amount_sats: amount_sats
    )

    redirect_to @budget, notice: "Versati #{BtcConversion.format_btc(amount_sats)} nel collateral del deal."
  rescue Budgets::InvestorCollateralTopUpService::Error => e
    redirect_to @budget, alert: e.message
  end

  private

  def set_budget
    @budget = Budget.find(params[:budget_id])
  end
end
