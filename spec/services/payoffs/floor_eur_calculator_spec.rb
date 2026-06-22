# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payoffs::FloorEurCalculator do
  # PAYOFF-SPEC §5 — K = 50_000 €/BTC, 6 mesi, 1%/mese, notional 5_000 €
  let(:notional_eur_cents) { 500_000 }
  let(:rate_bps_monthly) { 100 }
  let(:months_elapsed) { 6 }
  let(:liability_eur_cents) { 530_000 }

  def calc(spot:, holder_shares_cents: [notional_eur_cents], escrow_total_sats: 50_000_000, mining_fee_sats: 0)
    described_class.call(
      notional_eur_cents: notional_eur_cents,
      notional_total_cents: notional_eur_cents,
      holder_shares_cents: holder_shares_cents,
      spot_eur_per_btc: spot,
      rate_bps_monthly: rate_bps_monthly,
      months_elapsed: months_elapsed,
      escrow_total_sats: escrow_total_sats,
      mining_fee_sats: mining_fee_sats
    )
  end

  describe "PAYOFF-SPEC §5 — tre spot" do
    it "computes liability and holder sats at 25k, 50k, 100k" do
      expect(calc(spot: 25_000).liability_eur_cents).to eq(liability_eur_cents)
      expect(calc(spot: 25_000).total_holder_sats).to eq(21_200_000)
      expect(calc(spot: 50_000).total_holder_sats).to eq(10_600_000)
      expect(calc(spot: 100_000).total_holder_sats).to eq(5_300_000)
    end

    it "keeps the same € value when spot rises above K" do
      low = calc(spot: 50_000)
      high = calc(spot: 100_000)

      expect(low.liability_eur_cents).to eq(high.liability_eur_cents)
      expect(high.total_holder_sats).to be < low.total_holder_sats
      expect(BtcConversion.sats_to_eur(low.total_holder_sats, 50_000)).to be_within(1).of(5_300)
      expect(BtcConversion.sats_to_eur(high.total_holder_sats, 100_000)).to be_within(1).of(5_300)
    end
  end

  describe "PAYOFF-SPEC §5 — transfer 40% a cessionario" do
    it "splits total_holder_sats pro-rata (Alice 60%, Claude 40%)" do
      alice_share = 300_000
      claude_share = 200_000
      result = calc(spot: 50_000, holder_shares_cents: [alice_share, claude_share])

      expect(result.total_holder_sats).to eq(10_600_000)
      expect(result.holder_allocations[0].btc_sats).to eq(6_360_000)
      expect(result.holder_allocations[1].btc_sats).to eq(4_240_000)
    end
  end

  describe "PAYOFF-SPEC §7 — cap escrow" do
    it "limits holder payout when gross exceeds distributable" do
      result = calc(spot: 25_000, escrow_total_sats: 1_500_000, mining_fee_sats: 0)

      expect(result.gross_holder_sats).to eq(21_200_000)
      expect(result.total_holder_sats).to eq(1_500_000)
      expect(result.insolvent).to be(true)
      expect(result.investor_remainder_sats).to eq(0)
    end

    it "deducts mining fees before holder payout" do
      fee = Budget::ESTIMATED_SETTLEMENT_FEE_SATS
      escrow = 10_600_000 + fee
      result = calc(spot: 50_000, escrow_total_sats: escrow, mining_fee_sats: fee)

      expect(result.distributable_sats).to eq(10_600_000)
      expect(result.total_holder_sats).to eq(10_600_000)
      expect(result.investor_remainder_sats).to eq(0)
    end
  end
end
