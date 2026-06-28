# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dlc::ContractSetupService do
  let(:budget) do
    b = create(
      :budget,
      amount_eur_cents: 500_000,
      collateral_eur_cents: 500_000,
      rate_bps_monthly: 100,
      peg_eur_per_btc: 50_000,
      borrower_locked_sats: 10_000_000,
      investor_locked_sats: 10_000_000,
      maturity_block_height: 1_000,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 7, 1)
    )
    CollateralLock.create!(budget: b, amount_sats: 20_000_000, locked_at: Time.current)
    b
  end

  let(:oracle) { instance_double(Dlc::OracleClient) }
  let(:node) { instance_double(Dlc::NodeClient) }

  let(:announcement) do
    Dlc::OracleClient::Announcement.new(
      event_id: "deal-#{budget.id}", oracle_pubkey: "02ab", nonces: %w[n0 n1],
      num_digits: 20, unit: "EUR/BTC", precision: 0, maturity_epoch: 123, hex: "annhex", raw: {}
    )
  end

  let(:contract) do
    Dlc::NodeClient::Contract.new(
      contract_id: "c-1", funding_txid: "ab" * 32, funding_vout: 0,
      funding_address: "bcrt1q", status: "funded", raw: {}
    )
  end

  before do
    allow(oracle).to receive(:announce_numeric).and_return(announcement)
    allow(node).to receive(:create_contract).and_return(contract)
  end

  it "announces the event, funds the contract and persists a DlcContract" do
    result = described_class.call(budget: budget, oracle: oracle, node: node)

    expect(result).to be_a(DlcContract)
    expect(result).to be_funded
    expect(result.oracle_event_id).to eq("deal-#{budget.id}")
    expect(result.ddk_contract_id).to eq("c-1")
    expect(result.funding_outpoint).to eq("#{'ab' * 32}:0")
    expect(result.num_digits).to eq(20)
    expect(result.peg_collateral_sats).to eq(10_000_000)
    expect(result.investor_collateral_sats).to eq(10_000_000)
  end

  it "passes the FloorEUR payout schedule and collateral to the node" do
    described_class.call(budget: budget, oracle: oracle, node: node)

    expect(node).to have_received(:create_contract) do |args|
      expect(args[:oracle_announcement]).to eq("annhex")
      expect(args[:peg_collateral_sats]).to eq(10_000_000)
      expect(args[:investor_collateral_sats]).to eq(10_000_000)
      expect(args[:refund_locktime]).to eq(budget.refund_locktime_height)
      expect(args[:payouts]).to be_present
      expect(args[:payouts].first).to include(:outcome, :peg_sats, :investor_sats)
    end
  end

  it "is idempotent: a second call returns the existing contract" do
    first = described_class.call(budget: budget, oracle: oracle, node: node)
    second = described_class.call(budget: budget.reload, oracle: oracle, node: node)

    expect(second.id).to eq(first.id)
    expect(node).to have_received(:create_contract).once
  end

  it "raises a setup error when the oracle fails" do
    allow(oracle).to receive(:announce_numeric).and_raise(Dlc::OracleClient::Error, "boom")

    expect { described_class.call(budget: budget, oracle: oracle, node: node) }
      .to raise_error(described_class::Error, /Setup DLC fallito: boom/)
  end

  it "raises when the budget peg is missing" do
    budget.update!(peg_eur_per_btc: nil)

    expect { described_class.call(budget: budget, oracle: oracle, node: node) }
      .to raise_error(described_class::Error, /peg/)
  end
end
