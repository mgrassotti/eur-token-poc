# frozen_string_literal: true

module Api
  module V1
    module Integration
      class AdminFundReservesController < BaseController
        # Phase 2 primary path: fund any on-device BDK address (receive_address + amount_btc).
        # Optional test helper: user_email alone seeds a UserWallet address for deal-flow specs.
        def create
          amount_sats = BtcConversion.btc_to_sats(params.require(:amount_btc))
          address = normalized_receive_address(params[:receive_address])

          if address.blank? && params[:user_email].present?
            user = User.where(admin: false).find_by!(email: params[:user_email])
            address = ensure_test_reserve_address!(user)
          end

          if address.blank?
            return render json: { error: "address_required" }, status: :unprocessable_entity
          end

          result = L1::FundReceiveAddressService.call(address: address, amount_sats: amount_sats)

          render json: {
            schema_version: 1,
            receive_address: address,
            amount_sats: amount_sats,
            txid: result.txid,
            balance_sats: result.btc_account&.balance_sats
          }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "user_not_found" }, status: :not_found
        rescue L1::FundReceiveAddressService::Error => e
          render json: { error: "fund_failed", detail: e.message }, status: :service_unavailable
        end

        private

        def normalized_receive_address(value)
          value.to_s.strip.presence
        end

        # Integration/test only: register a bitcoind UserWallet receive address so
        # FundReceiveAddressService can credit btc_accounts.balance_sats for deal specs.
        def ensure_test_reserve_address!(user)
          account = user.btc_account
          return account.reserve_receive_address if account.reserve_receive_address.present?

          address = L1::UserWallet.for(user).receive_address
          account.update!(reserve_receive_address: address)
          address
        end
      end
    end
  end
end
