# frozen_string_literal: true

require "rails_helper"

# Demo-shaped deal: €1_000, 1 month @ 1%, settle at 50k peg.
# CET bucket peg_pot is 2_000_000 sats (€500 principal); FloorEUR liability
# is 2_020_000 sats (€505 incl. €5 interest). Alice holds 50% → 1_010_000 sats.
RSpec.describe "Demo interest at peg (€1000, 1 month @ 50k)" do
  let(:peg) { 50_000 }
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:claude) { create(:user, name: "Claude") }
  let(:david) { create(:user, name: "David") }

  let(:budget) do
    # Add 10,000 sats funding fee buffer required by Budgets::CreateService
    alice.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(100_000, peg) + 10_000)
    bob.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(200_000, peg) + 10_000)
    MarketRate.current.update!(btc_eur_per_btc: peg)
    created = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: 100_000,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 2, 1)
    )
    Budgets::ActivateService.call(budget: created, investor: bob)
    created
  end

  before do
    Tokens::TransferService.call(budget: budget, from_user: alice, to_user: claude, amount_cents: 50_000)
    Tokens::TransferService.call(budget: budget, from_user: claude, to_user: david, amount_cents: 10_000)
    advance_to_maturity!(budget)

    # CET bucket at peg: peg_pot covers principal only; investor side holds the rest.
    allow(Dlc::SettlementService).to receive(:call) do |budget:, end_btc_eur_rate:, **|
      @stub_settlement_end_rate = end_btc_eur_rate
      Dlc::SettlementService::Result.new(
        dlc_settlement: nil,
        cet_txid: "cet#{"0" * 61}",
        outcome: end_btc_eur_rate.to_i,
        peg_pot_sats: 2_000_000,
        investor_sats: 1_975_000
      )
    end
  end

  it "pays Alice 1_010_000 sats (€505) not the 1_000_000 peg-bucket pro-rata share" do
    result = Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: peg)

    expect(result.payoff.liability_eur_cents).to eq(101_000)
    expect(result.payoff.total_holder_sats).to eq(2_020_000)

    alice_payout = result.payouts.find { |p| p.user == alice }
    expect(alice_payout.btc_sats).to eq(1_010_000)
    expect(BtcConversion.sats_to_eur(alice_payout.btc_sats, peg)).to eq(505.0)
    expect(result.payouts.sum(&:btc_sats)).to eq(2_020_000)
  end

  it "passes exact FloorEUR holder_targets to Dlc::Distribution" do
    Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: peg)

    expect(Dlc::Distribution).to have_received(:call).with(
      hash_including(
        holder_targets: contain_exactly(
          { user: alice, sats: 1_010_000 },
          { user: claude, sats: 808_000 },
          { user: david, sats: 202_000 }
        )
      )
    )
  end
end
