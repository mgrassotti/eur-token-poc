# frozen_string_literal: true

class DashboardController < ApplicationController
  before_action :require_login

  def show
    @market_rate = MarketRate.current
    @spending_budget_total_cents = current_user.token_accounts.sum(:balance_cents)
    @spending_budgets = active_spending_budgets_for(current_user)
    @investment_sats = current_user.invested_budgets.active.sum(:investor_locked_sats)
    @investment_budgets = current_user.invested_budgets.active.where("investor_locked_sats > 0").order(:period_end)
    @investment_eur = savings_eur_value(@investment_sats, @market_rate)
    @savings_sats = current_user.balance_sats
    @transfer_budget = transferable_budget_for(current_user)
    @borrowed_budgets = current_user.borrowed_budgets.order(created_at: :desc)
    @pending_budgets = Budget.awaiting_investor.order(created_at: :desc)
    @investable_budgets = @pending_budgets.reject { |b| b.borrower_id == current_user.id }
    @savings_eur = savings_eur_value(@savings_sats, @market_rate)

    return unless admin?

    @active_budgets = Budget.active.order(created_at: :desc)
  end

  private

  def savings_eur_value(sats, market_rate)
    return unless market_rate&.set?

    BtcConversion.sats_to_eur(sats, market_rate.btc_eur_per_btc)
  end

  def transferable_budget_for(user)
    Budget.active
          .joins(:token_accounts)
          .where(token_accounts: { user_id: user.id })
          .where("token_accounts.balance_cents > 0")
          .order("token_accounts.updated_at DESC")
          .first
  end

  def active_spending_budgets_for(user)
    Budget.active
          .joins(:token_accounts)
          .where(token_accounts: { user_id: user.id })
          .where("token_accounts.balance_cents > 0")
          .distinct
          .order(:period_end)
  end
end
