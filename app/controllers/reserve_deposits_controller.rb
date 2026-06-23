# frozen_string_literal: true

class ReserveDepositsController < ApplicationController
  before_action :require_login
  before_action :require_l1!

  def new
    @default_btc = L1::DepositReserveService.default_btc_amount_for(current_user)
    @amount_btc = params[:amount_btc].presence || @default_btc
  end

  def create
    amount_sats = BtcConversion.btc_to_sats(params[:amount_btc])
    account = L1::DepositReserveService.call(user: current_user, amount_sats: amount_sats)
    redirect_to root_path,
                notice: "Deposito da #{L1::ExchangeWallet::DISPLAY_NAME} accreditato: #{BtcConversion.format_btc(amount_sats)} " \
                         "(saldo riserva: #{BtcConversion.format_btc(account.balance_sats)}). " \
                         "Catena simulata +#{L1::DepositReserveService::BLOCKS_PER_DEPOSIT} blocchi."
  rescue L1::DepositReserveService::Error => e
    redirect_to new_reserve_deposit_path, alert: e.message
  end

  private

  def require_l1!
    return if L1.enabled?

    redirect_to root_path, alert: "Deposito L1 disponibile solo con L1_ENABLED=1 e ./bin/regtest up"
  end
end
