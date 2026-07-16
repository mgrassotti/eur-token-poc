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
    @rgb_assets = rgb_assets_for(current_user)
    @rgb_node_error = @rgb_assets.nil?

    unless admin?
      @my_fund_accounts = Tokens::Spendable.fund_positions_for(current_user)
    end

    return unless admin?

    @active_budgets = Budget.active.order(created_at: :desc)
    @on_chain_wallets = L1::WalletInventoryService.call(market_rate: @market_rate)
    @fundable_users = User.where(admin: false).includes(:btc_account).order(:name)
    @user_receive_addresses = @fundable_users.to_h do |user|
      address = L1::ReserveReceiveAddressService.ensure!(user: user)
      [user.id.to_s, address]
    rescue L1::ReserveReceiveAddressService::Error
      [user.id.to_s, ""]
    end
  end

  private

  def savings_eur_value(sats, market_rate)
    return unless market_rate&.set?

    BtcConversion.sats_to_eur(sats, market_rate.btc_eur_per_btc)
  end

  def rgb_assets_for(user)
    return [] unless user.rgb_assignments.exists?
    return [] unless Rgb::Nodes.available_for?(user)

    Rgb::Nodes.for_user(user).list_assets.fetch("nia", [])
  rescue Rgb::LightningClient::Error, Rgb::Nodes::Error
    nil
  end
end
