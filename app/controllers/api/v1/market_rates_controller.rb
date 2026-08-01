# frozen_string_literal: true

module Api
  module V1
    class MarketRatesController < BaseController
      # Public: mobile clients need the rate for EUR display without login (Phase 2).
      skip_before_action :authenticate_api_user!

      def show
        market_rate = MarketRate.current

        render json: {
          schema_version: 1,
          btc_eur_per_btc: market_rate.btc_eur_per_btc&.to_f,
          bitcoin_block_height: market_rate.bitcoin_block_height,
          set: market_rate.set?,
          updated_at: market_rate.updated_at.iso8601
        }
      end
    end
  end
end
