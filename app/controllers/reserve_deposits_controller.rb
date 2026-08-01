# frozen_string_literal: true

class ReserveDepositsController < ApplicationController
  before_action :require_login

  def new
    @default_btc = 0.1 # Default amount for testing
    @amount_btc = params[:amount_btc].presence || @default_btc
    @receive_address = current_user.btc_account.reserve_receive_address
  end

  def create
    amount_sats = BtcConversion.btc_to_sats(params[:amount_btc])
    address = current_user.btc_account.reserve_receive_address

    unless address.present?
      return redirect_to new_reserve_deposit_path, 
        alert: "No receive address registered. Create a wallet in the mobile app first (Phase 2 BDK)."
    end

    result = L1::FundReceiveAddressService.call(address: address, amount_sats: amount_sats)
    account = current_user.btc_account.reload
    
    redirect_to root_path,
                notice: "Funded #{BtcConversion.format_btc(amount_sats)} BTC to your reserve. New balance: #{BtcConversion.format_btc(account.balance_sats)} BTC."
  rescue L1::FundReceiveAddressService::Error => e
    redirect_to new_reserve_deposit_path, alert: e.message
  end
end
