# frozen_string_literal: true

module Budgets
  class InvestorCollateralTopUpService
    class Error < StandardError; end

    def self.call(budget:, investor:, amount_sats:)
      new(budget:, investor:, amount_sats:).call
    end

    def initialize(budget:, investor:, amount_sats:)
      @budget = budget
      @investor = investor
      @amount_sats = amount_sats.to_i
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        investor.btc_account.lock!
        L1::SyncReserveBalanceService.call(user: investor)

        available_sats = ReserveRequirement.available_sats_for(investor)
        if available_sats < amount_sats
          raise Error,
                ReserveRequirement.insufficient_message(
                  label: "l'investitore",
                  required_sats: amount_sats,
                  available_sats: available_sats,
                  eur_per_btc: MarketRate.current.btc_eur_per_btc
                )
        end

        collateral = budget.collateral_lock.lock!
        collateral.update!(amount_sats: collateral.amount_sats + amount_sats)
        budget.update!(investor_locked_sats: budget.investor_locked_sats + amount_sats)
      end

      budget.reload
    end

    private

    attr_reader :budget, :investor, :amount_sats

    def validate!
      raise Error, "Il deal non è attivo" unless budget.active?
      raise Error, "Solo l'investitore del deal può versare collateral aggiuntivo" unless budget.investor_id == investor.id
      raise Error, "Importo non valido" unless amount_sats.positive?
      raise Error, "L'admin deve impostare il cambio BTC/€ corrente" unless MarketRate.current.set?
    end
  end
end
