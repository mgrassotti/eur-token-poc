# frozen_string_literal: true

class SettlementsController < ApplicationController
  before_action :require_login
  before_action :require_admin
  before_action :set_budget

  def new
    @market_rate = MarketRate.current
  end

  def create
    @result = Settlements::ExecuteService.call(
      budget: @budget,
      end_btc_eur_rate: params[:end_btc_eur_rate],
      set_by: current_user
    )
    render :show
  rescue Settlements::ExecuteService::Error => e
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  private

  def set_budget
    @budget = Budget.find(params[:budget_id])
    return if @budget.active?

    redirect_to @budget, alert: "Settlement is only available for active budgets."
  end
end
