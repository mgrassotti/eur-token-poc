# frozen_string_literal: true

module Budgets
  class InvestorYieldService
    class Error < StandardError; end

    PayoutResult = Data.define(:user, :btc_sats, :btc_eur_per_btc)

    def self.call(budget:)
      new(budget:).call
    end

    def initialize(budget:)
      @budget = budget
    end

    def call
      return [] unless budget.active?
      return [] unless budget.investor
      return [] unless MarketRate.current.set?

      rate = MarketRate.current.btc_eur_per_btc
      return [] unless rate.to_d.positive?

      budget.reload
      return [] if budget.pool_sats.zero?
      return [] if budget.minted_token_cents.zero?
      return [] unless budget.yield_eligible?(rate)

      sats_to_pay = yield_sats_delta(rate)
      return [] if sats_to_pay <= 0

      [pay_investor!(sats_to_pay, rate)]
    end

    private

    attr_reader :budget

    def yield_sats_delta(rate)
      token_eur = budget.minted_token_cents / 100.0
      pool_eur_at_floor = token_eur / Budget::INVESTOR_YIELD_LTV_THRESHOLD
      pool_sats_at_floor = BtcConversion.eur_cents_to_sats((pool_eur_at_floor * 100).round, rate)

      [budget.pool_sats - pool_sats_at_floor, 0].max
    end

    def pay_investor!(sats_to_pay, rate)
      investor = budget.investor

      ActiveRecord::Base.transaction do
        collateral = budget.collateral_lock.lock!
        raise Error, "Collateral deal insufficiente" if collateral.amount_sats < sats_to_pay
        raise Error, "Quota investor insufficiente" if budget.investor_locked_sats < sats_to_pay

        collateral.update!(amount_sats: collateral.amount_sats - sats_to_pay)
        budget.update!(investor_locked_sats: budget.investor_locked_sats - sats_to_pay)

        investor_btc = investor.btc_account.lock!
        investor_btc.update!(balance_sats: investor_btc.balance_sats + sats_to_pay)

        InvestorYieldPayout.create!(
          budget: budget,
          user: investor,
          btc_sats: sats_to_pay,
          btc_eur_per_btc: rate,
          paid_at: Time.current
        )
      end

      PayoutResult.new(user: investor, btc_sats: sats_to_pay, btc_eur_per_btc: rate)
    end
  end
end
