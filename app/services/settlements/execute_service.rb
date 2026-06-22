# frozen_string_literal: true

module Settlements
  class ExecuteService
    class Error < StandardError; end

    Payout = Data.define(
      :user,
      :token_cents,
      :btc_sats,
      :liability_eur_cents,
      :eur_at_settlement
    )

    def self.call(budget:, end_btc_eur_rate:, set_by: nil, force_liquidation: false)
      new(budget:, end_btc_eur_rate:, set_by:, force_liquidation:).call
    end

    def initialize(budget:, end_btc_eur_rate:, set_by: nil, force_liquidation: false)
      @budget = budget
      @end_btc_eur_rate = end_btc_eur_rate.to_d
      @set_by = set_by
      @force_liquidation = force_liquidation
    end

    def call
      validate!

      token_accounts = budget.token_accounts.lock.where("balance_cents > 0").order(:id).to_a
      payoff = Payoffs::FloorEurCalculator.call(
        notional_eur_cents: budget.notional_eur_cents,
        notional_total_cents: budget.amount_eur_cents,
        holder_shares_cents: token_accounts.map(&:balance_cents),
        spot_eur_per_btc: end_btc_eur_rate,
        rate_bps_monthly: budget.rate_bps_monthly,
        months_elapsed: budget.months_elapsed,
        escrow_total_sats: budget.pool_sats
      )

      payouts = []

      ActiveRecord::Base.transaction do
        token_accounts.each_with_index do |token_account, index|
          allocation = payoff.holder_allocations[index]
          btc_account = token_account.user.btc_account.lock!

          btc_account.update!(balance_sats: btc_account.balance_sats + allocation.btc_sats)
          payouts << Payout.new(
            user: token_account.user,
            token_cents: token_account.balance_cents,
            btc_sats: allocation.btc_sats,
            liability_eur_cents: payoff.liability_eur_cents,
            eur_at_settlement: (payoff.liability_eur_cents * token_account.balance_cents / budget.amount_eur_cents) / 100.0
          )

          token_account.update!(balance_cents: 0)
        end

        budget.collateral_lock.lock!

        raise Error, "Collateral insufficient for token redemptions" if payoff.investor_remainder_sats.negative?

        investor_btc = budget.investor.btc_account.lock!
        investor_btc.update!(balance_sats: investor_btc.balance_sats + payoff.investor_remainder_sats)

        settlement = Settlement.create!(
          budget: budget,
          end_btc_eur_rate: end_btc_eur_rate,
          total_btc_to_holders_sats: payoff.total_holder_sats,
          btc_to_investor_sats: payoff.investor_remainder_sats,
          executed_at: Time.current
        )

        budget.update!(status: :settled)

        market_rate_updated = update_market_rate!

        Result.new(
          settlement: settlement,
          payouts: payouts,
          payoff: payoff,
          borrower: budget.borrower,
          borrower_btc_sats: 0,
          investor: budget.investor,
          investor_btc_sats: payoff.investor_remainder_sats,
          investor_eur_at_end: BtcConversion.sats_to_eur(payoff.investor_remainder_sats, end_btc_eur_rate),
          peg_eur_per_btc: budget.peg_eur_per_btc,
          end_btc_eur_rate: end_btc_eur_rate,
          market_rate_updated: market_rate_updated
        )
      end
    end

    Result = Data.define(
      :settlement,
      :payouts,
      :payoff,
      :borrower,
      :borrower_btc_sats,
      :investor,
      :investor_btc_sats,
      :investor_eur_at_end,
      :peg_eur_per_btc,
      :end_btc_eur_rate,
      :market_rate_updated
    )

    private

    attr_reader :budget, :end_btc_eur_rate, :set_by, :force_liquidation

    def validate!
      raise Error, "Budget is not active" unless budget.active?
      raise Error, "End BTC/EUR rate must be positive" unless end_btc_eur_rate.positive?
      raise Error, "Budget peg is missing" unless budget.peg_set?
      raise Error, "Budget already settled" if budget.settlement.present?
      return if force_liquidation || budget.ready_for_settlement?

      raise Error, "Settlement disponibile dal blocco #{budget.maturity_block_height}"
    end

    def update_market_rate!
      return false unless set_by

      market_rate = MarketRate.current
      return false if market_rate.btc_eur_per_btc.to_d == end_btc_eur_rate

      market_rate.update!(btc_eur_per_btc: end_btc_eur_rate, set_by: set_by)
      true
    end
  end
end
