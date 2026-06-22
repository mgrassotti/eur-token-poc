# frozen_string_literal: true

module Payoffs
  # FloorEUR payoff — see docs/rgb-design/PAYOFF-SPEC.md
  class FloorEurCalculator
    HolderAllocation = Data.define(:share_cents, :btc_sats)

    Result = Data.define(
      :notional_eur_cents,
      :months_elapsed,
      :liability_eur_cents,
      :gross_holder_sats,
      :total_holder_sats,
      :distributable_sats,
      :investor_remainder_sats,
      :mining_fee_sats,
      :insolvent,
      :holder_allocations
    )

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(
      notional_eur_cents:,
      notional_total_cents:,
      holder_shares_cents:,
      spot_eur_per_btc:,
      rate_bps_monthly:,
      months_elapsed:,
      escrow_total_sats:,
      mining_fee_sats: Budget::ESTIMATED_SETTLEMENT_FEE_SATS
    )
      @notional_eur_cents = notional_eur_cents
      @notional_total_cents = notional_total_cents
      @holder_shares_cents = holder_shares_cents
      @spot_eur_per_btc = spot_eur_per_btc.to_d
      @rate_bps_monthly = rate_bps_monthly
      @months_elapsed = months_elapsed
      @escrow_total_sats = escrow_total_sats
      @mining_fee_sats = mining_fee_sats
    end

    def call
      liability = liability_eur_cents
      gross = gross_holder_sats(liability)
      distributable = [escrow_total_sats - mining_fee_sats, 0].max
      total_holder = [gross, distributable].min
      insolvent = gross > distributable

      Result.new(
        notional_eur_cents: notional_eur_cents,
        months_elapsed: months_elapsed,
        liability_eur_cents: liability,
        gross_holder_sats: gross,
        total_holder_sats: total_holder,
        distributable_sats: distributable,
        investor_remainder_sats: distributable - total_holder,
        mining_fee_sats: mining_fee_sats,
        insolvent: insolvent,
        holder_allocations: allocate_holders(total_holder)
      )
    end

    private

    attr_reader :notional_eur_cents, :notional_total_cents, :holder_shares_cents,
                :spot_eur_per_btc, :rate_bps_monthly, :months_elapsed,
                :escrow_total_sats, :mining_fee_sats

    def liability_eur_cents
      (notional_eur_cents * (10_000 + rate_bps_monthly * months_elapsed)) / 10_000
    end

    def gross_holder_sats(liability_eur_cents)
      ((liability_eur_cents * 100_000_000) / (spot_eur_per_btc * 100)).floor
    end

    def allocate_holders(total_holder_sats)
      return [] if holder_shares_cents.empty?
      raise ArgumentError, "notional_total must be positive" unless notional_total_cents.positive?

      allocations = []
      assigned = 0

      holder_shares_cents[0..-2].each do |share_cents|
        sats = ((total_holder_sats * share_cents) / notional_total_cents).floor
        allocations << HolderAllocation.new(share_cents: share_cents, btc_sats: sats)
        assigned += sats
      end

      last_share = holder_shares_cents.last
      last_sats = total_holder_sats - assigned
      allocations << HolderAllocation.new(share_cents: last_share, btc_sats: last_sats)

      allocations
    end
  end
end
