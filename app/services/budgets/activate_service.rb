# frozen_string_literal: true

module Budgets
  class ActivateService
    class Error < StandardError; end

    def self.call(budget:, investor:)
      new(budget:, investor:).call
    end

    def initialize(budget:, investor:)
      @budget = budget
      @investor = investor
    end

    def call
      validate!

      peg_eur_per_btc = budget.peg_eur_per_btc

      ActiveRecord::Base.transaction do
        investor_btc = investor.btc_account.lock!
        collateral_sats = budget.collateral_sats_at_peg(peg_eur_per_btc)

        raise Error, "Saldo insufficiente sul conto risparmio" if investor_btc.balance_sats < collateral_sats

        investor_btc.update!(balance_sats: investor_btc.balance_sats - collateral_sats)

        total_locked_sats = collateral_sats + budget.borrower_locked_sats

        budget.update!(
          investor: investor,
          investor_locked_sats: collateral_sats,
          status: :active
        )

        CollateralLock.create!(
          budget: budget,
          amount_sats: total_locked_sats,
          locked_at: Time.current
        )

        TokenAccount.create!(
          user: budget.borrower,
          budget: budget,
          balance_cents: budget.amount_eur_cents
        )
      end

      budget.reload
    end

    private

    attr_reader :budget, :investor

    def validate!
      raise Error, "Budget is not pending" unless budget.pending?
      raise Error, "Investor cannot be the borrower" if investor.id == budget.borrower_id
      raise Error, "Budget peg is missing" unless budget.peg_set?
      raise Error, "Admin must set current BTC/EUR rate" unless MarketRate.current.set?
    end
  end
end
