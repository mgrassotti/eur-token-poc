# frozen_string_literal: true

module Api
  module V1
    module Integration
      class AdminFundReservesController < BaseController
        # Mirrors Admin::ReserveDepositsController#create (paste address + send BTC).
        def create
          user = User.where(admin: false).find_by!(email: params.require(:user_email))
          amount_sats = BtcConversion.btc_to_sats(params.require(:amount_btc))
          address = normalized_receive_address(params[:receive_address])
          expected = L1::ReserveReceiveAddressService.ensure!(user: user)

          if address.present? && address != expected
            return render json: { error: "address_mismatch", expected: expected }, status: :unprocessable_entity
          end

          L1::DepositReserveService.call(user: user, amount_sats: amount_sats)
          account = user.btc_account.reload

          render json: {
            schema_version: 1,
            user_email: user.email,
            receive_address: expected,
            amount_sats: amount_sats,
            balance_sats: account.balance_sats
          }
        rescue L1::DepositReserveService::Error, L1::ReserveReceiveAddressService::Error => e
          render json: { error: "fund_failed", detail: e.message }, status: :service_unavailable
        end

        private

        def normalized_receive_address(value)
          value.to_s.strip.presence
        end
      end
    end
  end
end
