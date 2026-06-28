# frozen_string_literal: true

module Dlc
  # Builds the FloorEUR payout schedule for a DLC numeric contract.
  #
  # The oracle attests the BTC price (EUR/BTC) at maturity; the contract must
  # map every possible price outcome to a {peg_sats, investor_sats} split. We
  # delegate the economics to Payoffs::FloorEurCalculator (single source of
  # truth) and sample it at a handful of price anchors around the peg. The ddk
  # shim interpolates between anchors to obtain the full per-outcome CET set —
  # a PoC-grade approximation of a real DLC payout curve.
  class PayoutCurve
    Point = Data.define(:outcome, :peg_sats, :investor_sats)

    # Price anchors as multipliers of the peg. Denser below the peg where the
    # FloorEUR liability/price curve bends (insolvency region).
    DEFAULT_PRICE_MULTIPLIERS = [0.1, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 5.0].freeze

    def self.for(budget:, num_digits: Config.num_digits, base: Config.base)
      new(budget:, num_digits:, base:).call
    end

    def initialize(budget:, num_digits: Config.num_digits, base: Config.base)
      @budget = budget
      @num_digits = num_digits
      @base = base
    end

    def call
      raise ArgumentError, "Budget peg mancante" unless budget.peg_set?

      price_anchors.map { |price| point_for(price) }
    end

    private

    attr_reader :budget, :num_digits, :base

    def max_outcome
      Dlc::Numeric.max_value(num_digits: num_digits, base: base)
    end

    def price_anchors
      peg = budget.peg_eur_per_btc.to_i
      anchors = DEFAULT_PRICE_MULTIPLIERS.map { |m| (peg * m).round }
      anchors.push(1, max_outcome)
      anchors.map { |p| p.clamp(1, max_outcome) }.uniq.sort
    end

    def point_for(price)
      payoff = Payoffs::FloorEurCalculator.call(
        notional_eur_cents: budget.notional_eur_cents,
        notional_total_cents: budget.amount_eur_cents,
        holder_shares_cents: [budget.amount_eur_cents],
        spot_eur_per_btc: price,
        rate_bps_monthly: budget.rate_bps_monthly,
        months_elapsed: budget.symbolic_months_duration,
        escrow_total_sats: budget.pool_sats
      )

      Point.new(
        outcome: price,
        peg_sats: payoff.total_holder_sats,
        investor_sats: payoff.investor_remainder_sats
      )
    end
  end
end
