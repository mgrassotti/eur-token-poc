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
        investor_btc = investor.btc_account.lock!
        raise Error, "Saldo insufficiente sul conto di riserva" if investor_btc.balance_sats < amount_sats

        investor_btc.update!(balance_sats: investor_btc.balance_sats - amount_sats)

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
    end
  end
end
