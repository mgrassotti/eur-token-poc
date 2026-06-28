# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dlc::SettlementService do
  let(:budget) do
    create(
      :budget,
      amount_eur_cents: 500_000,
      collateral_eur_cents: 500_000,
      peg_eur_per_btc: 50_000,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 7, 1)
    )
  end

  let!(:dlc_contract) do
    DlcContract.create!(
      budget: budget,
      oracle_event_id: "deal-#{budget.id}",
      oracle_announcement: "annhex",
      ddk_contract_id: "c-1",
      funding_txid: "ab" * 32,
      funding_vout: 0,
      num_digits: 20,
      status: :funded
    )
  end

  let(:oracle) { instance_double(Dlc::OracleClient) }
  let(:node) { instance_double(Dlc::NodeClient) }

  let(:attestation) do
    Dlc::OracleClient::Attestation.new(
      event_id: "deal-#{budget.id}", oracle_pubkey: "02ab", outcome: 60_000,
      digits: nil, signatures: %w[s0 s1], hex: "atthex", raw: {}
    )
  end

  let(:execution) do
    Dlc::NodeClient::Execution.new(
      cet_txid: "cd" * 32, outcome: 60_000, peg_sats: 8_000_000,
      investor_sats: 12_000_000, raw: {}
    )
  end

  before do
    allow(oracle).to receive(:attest_numeric).and_return(attestation)
    allow(node).to receive(:execute_contract).and_return(execution)
  end

  it "attests the outcome, executes the CET and persists a DlcSettlement" do
    result = described_class.call(budget: budget, end_btc_eur_rate: 60_000, oracle: oracle, node: node)

    expect(result.cet_txid).to eq("cd" * 32)
    expect(result.outcome).to eq(60_000)
    expect(result.peg_pot_sats).to eq(8_000_000)
    expect(result.investor_sats).to eq(12_000_000)

    settlement = budget.reload.dlc_settlement
    expect(settlement).to be_executed
    expect(settlement.attestation).to eq("atthex")
    expect(dlc_contract.reload).to be_executed
  end

  it "passes the integer price outcome to the oracle" do
    described_class.call(budget: budget, end_btc_eur_rate: 60_000.99, oracle: oracle, node: node)

    expect(oracle).to have_received(:attest_numeric)
      .with(event_id: "deal-#{budget.id}", outcome: 60_000, maturity_epoch: dlc_contract.maturity_epoch)
    expect(node).to have_received(:execute_contract).with(contract_id: "c-1", attestation: "atthex")
  end

  it "is idempotent on an already-executed settlement" do
    described_class.call(budget: budget, end_btc_eur_rate: 60_000, oracle: oracle, node: node)
    described_class.call(budget: budget.reload, end_btc_eur_rate: 60_000, oracle: oracle, node: node)

    expect(node).to have_received(:execute_contract).once
    expect(budget.reload.dlc_settlement).to be_present
  end

  it "raises when there is no DLC contract" do
    budget.dlc_contract.destroy!

    expect { described_class.call(budget: budget.reload, end_btc_eur_rate: 60_000, oracle: oracle, node: node) }
      .to raise_error(described_class::Error, /Nessun contratto DLC/)
  end

  it "wraps node failures in a settlement error" do
    allow(node).to receive(:execute_contract).and_raise(Dlc::NodeClient::Error, "cet rejected")

    expect { described_class.call(budget: budget, end_btc_eur_rate: 60_000, oracle: oracle, node: node) }
      .to raise_error(described_class::Error, /Settlement DLC fallito: cet rejected/)
  end
end
