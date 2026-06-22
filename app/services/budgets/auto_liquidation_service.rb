# frozen_string_literal: true

module Budgets
  class AutoLiquidationService
    def self.call(market_rate: MarketRate.current, set_by: nil)
      new(market_rate:, set_by:).call
    end

    def initialize(market_rate:, set_by: nil)
      @market_rate = market_rate
      @set_by = set_by
    end

    def call
      return [] unless market_rate.set?

      results = []

      Budget.active.order(:id).find_each do |budget|
        next unless liquidation_needed?(budget)

        result = Settlements::ExecuteService.call(
          budget: budget,
          end_btc_eur_rate: market_rate.btc_eur_per_btc,
          set_by: set_by,
          force_liquidation: true
        )
        results << result
      end

      results
    end

    private

    attr_reader :market_rate, :set_by

    def liquidation_needed?(budget)
      return false unless budget.minted_token_cents.positive?
      return false unless budget.pool_sats.positive?

      budget.liquidation_threshold_reached?(market_rate.btc_eur_per_btc)
    end
  end
end
