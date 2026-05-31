# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :require_login
  before_action :set_budget, only: %i[show activate]

  def index
    @budgets = Budget.includes(:borrower, :investor).order(created_at: :desc)
  end

  def show
  end

  def new
    @budget = current_user.borrowed_budgets.build(
      period_start: Date.current.beginning_of_month,
      period_end: Date.current.end_of_month
    )
  end

  def create
    @budget = current_user.borrowed_budgets.build(budget_params)

    if @budget.save
      redirect_to @budget, notice: "Budget request created. Waiting for an investor."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def activate
    if @budget.borrower_id == current_user.id
      redirect_to @budget, alert: "Cannot invest in your own budget."
      return
    end

    Budgets::ActivateService.call(
      budget: @budget,
      investor: current_user,
      peg_eur_per_btc: params[:peg_eur_per_btc]
    )
    redirect_to @budget, notice: "Budget activated. Tokens minted for #{@budget.borrower.name}."
  rescue Budgets::ActivateService::Error => e
    redirect_to @budget, alert: e.message
  end

  private

  def set_budget
    @budget = Budget.find(params[:id])
  end

  def budget_params
    permitted = params.require(:budget).permit(:amount_eur, :collateral_eur, :period_start, :period_end)
    attrs = {
      period_start: permitted[:period_start],
      period_end: permitted[:period_end]
    }
    attrs[:amount_eur_cents] = (permitted[:amount_eur].to_d * 100).round if permitted[:amount_eur].present?
    attrs[:collateral_eur_cents] = (permitted[:collateral_eur].to_d * 100).round if permitted[:collateral_eur].present?
    attrs
  end
end
