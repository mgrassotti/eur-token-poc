# frozen_string_literal: true

module Api
  module V1
    class ReserveController < BaseController
      def show
        address = L1::ReserveReceiveAddressService.ensure!(user: current_user)
        balance_sats = L1::ReserveBalance.sats_for(current_user)

        render json: {
          schema_version: 1,
          network: "regtest",
          receive_address: address,
          balance_sats: balance_sats,
          wallet_name: current_user.btc_account.bitcoind_wallet_name,
          instructions: "Send BTC on regtest to this address. An admin funds via Exchange wallet, then refresh or tap Sync."
        }
      rescue L1::ReserveReceiveAddressService::Error => e
        render json: { error: "reserve_unavailable", detail: e.message }, status: :service_unavailable
      end

      def sync
        L1::SyncReserveBalanceService.call(user: current_user)
        account = current_user.btc_account.reload

        render json: {
          schema_version: 1,
          balance_sats: account.balance_sats,
          synced_at: Time.current.iso8601
        }
      rescue Bitcoind::Error => e
        render json: { error: "sync_failed", detail: e.message }, status: :service_unavailable
      end
    end
  end
end
