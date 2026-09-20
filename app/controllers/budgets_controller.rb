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
    @market_rate = MarketRate.current
    @max_borrowable_eur = Budgets::ReserveRequirement.max_eur_for(current_user)
    default_eur = [@max_borrowable_eur, 1_000.0].min
    default_eur = 1_000.0 if default_eur <= 0

    @budget = current_user.borrowed_budgets.build(
      period_start: Date.current,
      period_end: Date.current + 1.month,
      amount_eur_cents: (default_eur * 100).round
    )
  end

  def create
    @budget = Budgets::CreateService.call(
      borrower: current_user,
      amount_eur_cents: budget_params[:amount_eur_cents],
      period_start: budget_params[:period_start],
      period_end: budget_params[:period_end]
    )
    redirect_to @budget, notice: t("flash.budgets.created")
  rescue Budgets::CreateService::Error => e
    @market_rate = MarketRate.current
    @max_borrowable_eur = Budgets::ReserveRequirement.max_eur_for(current_user)
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
      redirect_to @budget, alert: t("flash.budgets.cannot_invest_own")
      return
    end

    unless MarketRate.current.set?
      redirect_to @budget, alert: t("services.budgets.create.market_rate_required")
      return
    end

    builder = Budgets::WalletFundingBuilder.new(budget: @budget, investor: current_user)
    budget = Budgets::ActivateService.call(
      budget: @budget,
      investor: current_user,
      funding: builder.call,
      auto_sign_wallets: builder.wallets
    )
    notice = t("flash.budgets.activated", amount: BtcConversion.format_btc(budget.investor_locked_sats))
    if budget.l1_multisig_provisioned?
      notice += " #{t("flash.budgets.escrow_provisioned", outpoint: budget.escrow_outpoint)}"
    end
    redirect_to budget, notice: notice
    rescue Budgets::ActivateService::Error, L1::ProvisionEscrowService::Error,
         Rgb::LightningClient::Error, Rgb::Nodes::Error, Rgb::WalletSetupService::Error,
         Rgb::LibIssueService::Error, Rgb::IssueService::Error,
         Dlc::ContractSetupService::Error => e
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
