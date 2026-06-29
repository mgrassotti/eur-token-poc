# frozen_string_literal: true

require "rails_helper"

RSpec.describe Settlements::ExecuteService, "DLC settlement path" do
  let(:peg) { 50_000 }
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }

  let(:budget) do
    alice.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(500_000, peg))
    bob.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(1_000_000, peg))
    MarketRate.current.update!(btc_eur_per_btc: peg)
    created = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: 500_000,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 7, 1)
    )
    Budgets::ActivateService.call(budget: created, investor: bob)
    created
  end

  let(:cet_txid) { "cd" * 32 }

  before do
    advance_to_maturity!(budget)
    DlcContract.create!(
      budget: budget,
      oracle_event_id: "deal-#{budget.id}",
      ddk_contract_id: "c-1",
      funding_txid: "ab" * 32,
      funding_vout: 0,
      num_digits: 20,
      status: :funded
    )
    allow(Dlc::Config).to receive(:enabled?).and_return(true)
    allow(Dlc::SettlementService).to receive(:call).and_return(
      Dlc::SettlementService::Result.new(
        dlc_settlement: nil, cet_txid: cet_txid, outcome: peg,
        peg_pot_sats: 10_600_000, investor_sats: 2
      )
    )
    allow(Dlc::Distribution).to receive(:call).and_return([])
  end

  it "executes the CET via Dlc::SettlementService instead of the escrow PSBT" do
    described_class.call(budget: budget, end_btc_eur_rate: peg)

    expect(Dlc::SettlementService).to have_received(:call).with(budget: budget, end_btc_eur_rate: peg)
    expect(Dlc::Distribution).to have_received(:call)
      .with(budget: budget, peg_pot_sats: 10_600_000, shares: kind_of(Array))
    expect(L1::SettlementPsbtService).not_to have_received(:broadcast!)
    expect(budget.reload).to be_settled
    expect(budget.recovery_package["settlement_txid"]).to eq(cet_txid)
    expect(budget.recovery_package["dlc"]).to be_present
  end

  it "falls back to the escrow PSBT when the DLC contract is not funded" do
    budget.dlc_contract.update!(status: :announced)

    described_class.call(budget: budget, end_btc_eur_rate: peg)

    expect(Dlc::SettlementService).not_to have_received(:call)
    expect(L1::SettlementPsbtService).to have_received(:broadcast!)
  end
end
