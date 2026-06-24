# frozen_string_literal: true

class DashboardController < ApplicationController
  before_action :require_login

  def show
    @market_rate = MarketRate.current
    @spending_budget_total_cents = Tokens::Spendable.total_cents_for(current_user)
    @investment_sats = current_user.invested_budgets.active.sum(:investor_locked_sats)
    @investment_budgets = current_user.invested_budgets.active.where("investor_locked_sats > 0").order(:period_end)
    @investment_eur = savings_eur_value(@investment_sats, @market_rate)
    @savings_sats = Budgets::ReserveRequirement.available_sats_for(current_user)
    @spendable_token_cents = Tokens::Spendable.total_cents_for(current_user)
    @borrowed_budgets = current_user.borrowed_budgets.order(created_at: :desc)
    @pending_budgets = Budget.awaiting_investor.order(created_at: :desc)
    @investable_budgets = @pending_budgets.reject { |b| b.borrower_id == current_user.id }
    @savings_eur = savings_eur_value(@savings_sats, @market_rate)
    @margin_call_budgets = Budgets::MarginCall.budgets_for(current_user, market_rate: @market_rate)

    unless admin?
      fund_budget_ids = (
        current_user.borrowed_budgets.where.not(status: :pending).pluck(:id) +
        current_user.received_token_transfers.distinct.pluck(:budget_id)
      ).uniq

      @my_fund_accounts = current_user.token_accounts
        .includes(:budget)
        .where(budget_id: fund_budget_ids)
        .where("balance_cents > 0")
        .order(created_at: :desc)
    end

    return unless admin?

    @active_budgets = Budget.active.order(created_at: :desc)
    @on_chain_wallets = L1::WalletInventoryService.call(market_rate: @market_rate)
  end

  private

  def savings_eur_value(sats, market_rate)
    return unless market_rate&.set?

    BtcConversion.sats_to_eur(sats, market_rate.btc_eur_per_btc)
  end
end
