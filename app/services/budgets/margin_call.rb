# frozen_string_literal: true

module Budgets
  module MarginCall
    module_function

    def budgets_for(investor, market_rate: MarketRate.current)
      return [] unless market_rate.set?

      rate = market_rate.btc_eur_per_btc
      investor.invested_budgets.active.order(:id).select do |budget|
        budget.margin_call_threshold_reached?(rate)
      end
    end
  end
end
