# frozen_string_literal: true

class TokenTransfersController < ApplicationController
  before_action :require_login
  before_action :load_transfer_context

  def new
    @users = User.where(admin: false).where.not(id: current_user.id).order(:name)
  end

  def create
    to_user = User.where(admin: false).find(params[:to_user_id])
    amount_cents = (params[:amount_eur].to_d * 100).round

    parts = Tokens::WalletTransferService.call(
      from_user: current_user,
      to_user: to_user,
      amount_cents: amount_cents,
      preferred_budget: @preferred_budget
    )

    notice = transfer_notice(to_user:, amount_cents:, parts:)
    redirect_to root_path, notice: notice
  rescue Tokens::WalletTransferService::Error => e
    flash.now[:alert] = e.message
    @users = User.where(admin: false).where.not(id: current_user.id).order(:name)
    render :new, status: :unprocessable_entity
  end

  private

  def load_transfer_context
    @preferred_budget = Budget.find(params[:budget_id]) if params[:budget_id].present?
    @spendable_accounts = Tokens::Spendable.accounts_for(current_user).to_a
    @spendable_total_cents = @spendable_accounts.sum(&:balance_cents)

    return if @spendable_total_cents.positive?

    redirect_to root_path, alert: "Nessun saldo EURT disponibile sui deal attivi."
  end

  def transfer_notice(to_user:, amount_cents:, parts:)
    base = "Inviati #{BtcConversion.format_eur(amount_cents)} a #{to_user.name}."
    return base if parts.size == 1

    deal_ids = parts.map { |part| "##{part.budget.id}" }.join(", ")
    "#{base} Prelevato da #{parts.size} deal (#{deal_ids})."
  end
end
