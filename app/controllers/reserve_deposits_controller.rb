# frozen_string_literal: true

class ReserveDepositsController < ApplicationController
  before_action :require_login

  def new
    @default_btc = L1::DepositReserveService.default_btc_amount_for(current_user)
    @amount_btc = params[:amount_btc].presence || @default_btc
  end

  def create
    amount_sats = BtcConversion.btc_to_sats(params[:amount_btc])
    account = L1::DepositReserveService.call(user: current_user, amount_sats: amount_sats)
    redirect_to root_path,
                notice: t("flash.reserve_deposits.created",
                  wallet_name: L1::ExchangeWallet::DISPLAY_NAME,
                  amount: BtcConversion.format_btc(amount_sats),
                  balance: BtcConversion.format_btc(account.balance_sats),
                  blocks: L1::DepositReserveService::BLOCKS_PER_DEPOSIT)
  rescue L1::DepositReserveService::Error => e
    redirect_to new_reserve_deposit_path, alert: e.message
  end
end
