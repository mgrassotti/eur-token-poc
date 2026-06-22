# frozen_string_literal: true

module Budgets
  class AutoSettleService
    class Error < StandardError; end

    def self.call
      new.call
    end

    def call
      results = []

      loop do
        budget = Budget.active.order(:created_at).find(&:ready_for_settlement?)
        break unless budget

        rate = MarketRate.current.btc_eur_per_btc
        unless rate.present? && rate.positive?
          raise Error, "Cambio BTC/€ non impostato: impossibile eseguire il settlement automatico"
        end

        results << Settlements::ExecuteService.call(
          budget: budget,
          end_btc_eur_rate: rate,
          set_by: User.admins.first
        )
      end

      results
    end
  end
end
