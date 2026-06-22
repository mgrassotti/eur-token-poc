# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :require_login
  before_action :require_admin, only: :index
  before_action :set_budget, only: %i[show activate]

  def index
    @budgets = Budget.includes(:borrower, :investor).order(created_at: :desc)
  end

  def show
    @market_rate = MarketRate.current
  end

  def new
    @budget = current_user.borrowed_budgets.build(
      period_start: Date.current,
      period_end: Date.current + 1.month
    )
  end

  def create
    @budget = Budgets::CreateService.call(
      borrower: current_user,
      amount_eur_cents: budget_params[:amount_eur_cents],
      period_start: budget_params[:period_start],
      period_end: budget_params[:period_end]
    )
    redirect_to @budget, notice: "Budget spesa creato. In attesa di un investitore."
  rescue Budgets::CreateService::Error => e
    @budget = current_user.borrowed_budgets.build(
      period_start: budget_params[:period_start],
      period_end: budget_params[:period_end]
    )
    @budget.amount_eur_cents = budget_params[:amount_eur_cents]
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def activate
    if @budget.borrower_id == current_user.id
      redirect_to @budget, alert: "Cannot invest in your own budget."
      return
    end

    unless MarketRate.current.set?
      redirect_to @budget, alert: "L'admin deve impostare il cambio BTC/€ corrente."
      return
    end

    budget = Budgets::ActivateService.call(
      budget: @budget,
      investor: current_user
    )
    redirect_to budget, notice: "Budget attivato. #{BtcConversion.format_btc(budget.investor_locked_sats)} decurtati dal conto di riserva."
  rescue Budgets::ActivateService::Error => e
    redirect_to @budget, alert: e.message
  end

  private

  def set_budget
    @budget = Budget.find(params[:id])
  end

  def budget_params
    permitted = params.require(:budget).permit(:amount_eur, :period_start, :period_end)
    attrs = {
      period_start: permitted[:period_start],
      period_end: permitted[:period_end]
    }
    attrs[:amount_eur_cents] = (permitted[:amount_eur].to_d * 100).round if permitted[:amount_eur].present?
    attrs
  end
end
