# frozen_string_literal: true

module Budgets
  class ActivateService
    class Error < StandardError; end

    def self.call(budget:, investor:, peg_eur_per_btc:)
      new(budget:, investor:, peg_eur_per_btc:).call
    end

    def initialize(budget:, investor:, peg_eur_per_btc:)
      @budget = budget
      @investor = investor
      @peg_eur_per_btc = peg_eur_per_btc.to_d
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        investor_btc = investor.btc_account.lock!
        collateral_sats = budget.collateral_sats_at_peg(peg_eur_per_btc)

        raise Error, "Insufficient BTC balance for collateral" if investor_btc.balance_sats < collateral_sats

        investor_btc.update!(balance_sats: investor_btc.balance_sats - collateral_sats)

        budget.update!(
          investor: investor,
          peg_eur_per_btc: peg_eur_per_btc,
          status: :active
        )

        CollateralLock.create!(
          budget: budget,
          amount_sats: collateral_sats,
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

    attr_reader :budget, :investor, :peg_eur_per_btc

    def validate!
      raise Error, "Budget is not pending" unless budget.pending?
      raise Error, "Investor cannot be the borrower" if investor.id == budget.borrower_id
      raise Error, "Peg rate must be positive" unless peg_eur_per_btc.positive?
    end
  end
end
