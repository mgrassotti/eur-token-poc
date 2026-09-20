# frozen_string_literal: true

module Admin
  class ReserveDepositsController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def create
      address = normalized_receive_address(params[:receive_address])
      amount_sats = BtcConversion.btc_to_sats(params[:amount_btc])

      unless address.present?
        return redirect_to root_path, alert: t("flash.admin.reserve_deposits.address_required")
      end

      # Phase 2: Send on-chain to the pasted BDK address. No user lookup —
      # mobile wallets are client-side; balance appears after Electrum sync.
      result = L1::FundReceiveAddressService.call(address: address, amount_sats: amount_sats)

      redirect_to root_path,
                  notice: t(
                    "flash.admin.reserve_deposits.created",
                    wallet_name: L1::ExchangeWallet::DISPLAY_NAME,
                    amount: BtcConversion.format_btc(amount_sats),
                    address: address,
                    txid: result.txid
                  )
    rescue L1::FundReceiveAddressService::Error => e
      redirect_to root_path, alert: e.message
    end

    private

    def normalized_receive_address(value)
      value.to_s.strip.presence
    end
  end
end
