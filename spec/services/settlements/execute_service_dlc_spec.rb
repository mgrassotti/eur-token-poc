# frozen_string_literal: true

require "rails_helper"

RSpec.describe Settlements::ExecuteService, "DLC settlement path" do
  let(:peg) { 50_000 }
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }

  let(:budget) do
    # Add 10,000 sats funding fee buffer required by Budgets::CreateService
    alice.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(500_000, peg) + 10_000)
    bob.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(1_000_000, peg) + 10_000)
    MarketRate.current.update!(btc_eur_per_btc: peg)
    created = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: 500_000,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 7, 1)
    )
    unit_activate_budget!(created, investor: bob)
    created
  end

  let(:cet_txid) { "cd" * 32 }

  before do
    advance_to_maturity!(budget)
    # A funded DLC contract is seeded at activation (see l1_unit_stubs).
    allow(Dlc::SettlementService).to receive(:call).and_return(
      Dlc::SettlementService::Result.new(
        dlc_settlement: nil, cet_txid: cet_txid, outcome: peg,
        peg_pot_sats: 10_600_000, investor_sats: 2
      )
    )
    allow(Dlc::Distribution).to receive(:call) do |budget:, holder_targets:, **|
      holder_targets.map do |target|
        Dlc::Distribution::Payout.new(
          user: target[:user], sats: target[:sats], address: "stub-#{target[:user].id}", txid: "dist#{"0" * 61}"
        )
      end
    end
  end

  it "executes the CET via Dlc::SettlementService and distributes exact FloorEUR targets" do
    described_class.call(budget: budget, end_btc_eur_rate: peg)

    expect(Dlc::SettlementService).to have_received(:call).with(budget: budget, end_btc_eur_rate: peg)
    expect(Dlc::Distribution).to have_received(:call).with(
      budget: budget,
      peg_pot_sats: 10_600_000,
      shares: kind_of(Array),
      holder_targets: kind_of(Array)
    )
    expect(budget.reload).to be_settled
    expect(budget.recovery_package["settlement_txid"]).to eq(cet_txid)
    expect(budget.recovery_package["dlc"]).to be_present
  end

  it "raises when the DLC contract is not funded" do
    budget.dlc_contract.update!(status: :announced)

    expect do
      described_class.call(budget: budget, end_btc_eur_rate: peg)
    end.to raise_error(Settlements::ExecuteService::Error, /DLC non finanziato/)

    expect(Dlc::SettlementService).not_to have_received(:call)
  end
end
