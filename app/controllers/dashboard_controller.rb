# frozen_string_literal: true

class DashboardController < ApplicationController
  before_action :require_login

  def show
    @token_accounts = current_user.token_accounts.includes(:budget).where("balance_cents > 0")
    @borrowed_budgets = current_user.borrowed_budgets.order(created_at: :desc)
    @pending_budgets = Budget.awaiting_investor.order(created_at: :desc)
    @investable_budgets = @pending_budgets.reject { |b| b.borrower_id == current_user.id }
  end
end
