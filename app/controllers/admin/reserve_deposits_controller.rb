# frozen_string_literal: true

module Admin
  class ReserveDepositsController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def create
      address = normalized_receive_address(params[:receive_address])
      amount_sats = BtcConversion.btc_to_sats(params[:amount_btc])

      # Find user by their receive address
      user = User.where(admin: false).find do |u|
        begin
          L1::ReserveReceiveAddressService.ensure!(user: u) == address
        rescue L1::ReserveReceiveAddressService::Error
          false
        end
      end

      unless user
        return redirect_to root_path, alert: t("flash.admin.reserve_deposits.address_not_found")
      end

      L1::DepositReserveService.call(user: user, amount_sats: amount_sats)
      account = user.btc_account.reload

      redirect_to root_path,
                  notice: t(
                    "flash.admin.reserve_deposits.created",
                    wallet_name: L1::ExchangeWallet::DISPLAY_NAME,
                    amount: BtcConversion.format_btc(amount_sats),
                    address: address,
                    balance: BtcConversion.format_btc(account.balance_sats)
                  )
    rescue L1::DepositReserveService::Error, L1::ReserveReceiveAddressService::Error => e
      redirect_to root_path, alert: e.message
    end

    private

    def normalized_receive_address(value)
      value.to_s.strip.presence
    end
  end
end
