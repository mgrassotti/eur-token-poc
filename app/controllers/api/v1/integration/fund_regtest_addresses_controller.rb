# frozen_string_literal: true

module Api
  module V1
    module Integration
      # Sends regtest BTC to an arbitrary address (e.g. on-device BDK receive address).
      class FundRegtestAddressesController < BaseController
        def create
          address = params.require(:address).to_s.strip
          amount_sats = BtcConversion.btc_to_sats(params.require(:amount_btc))

          harness = L1::RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET)
          txid = harness.fund_address!(address, sats: amount_sats)
          # Give electrs time to index the funding tx before mobile BDK sync.
          harness.mine_blocks(2)

          render json: {
            schema_version: 1,
            address: address,
            amount_sats: amount_sats,
            txid: txid
          }
        rescue StandardError => e
          render json: { error: "fund_failed", detail: e.message }, status: :service_unavailable
        end
      end
    end
  end
end
