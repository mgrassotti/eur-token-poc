# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dlc::ContractSetupService do
  let(:investor) { create(:user, name: "Investor") }

  let(:budget) do
    b = create(
      :budget,
      amount_eur_cents: 500_000,
      collateral_eur_cents: 500_000,
      rate_bps_monthly: 100,
      peg_eur_per_btc: 50_000,
      borrower_locked_sats: 10_000_000,
      investor_locked_sats: 10_000_000,
      investor: investor,
      maturity_block_height: 1_000,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 7, 1)
    )
    CollateralLock.create!(budget: b, amount_sats: 20_000_000, locked_at: Time.current)
    b
  end

  let(:oracle) { instance_double(Dlc::OracleClient) }
  let(:node) { instance_double(Dlc::NodeClient) }
  let(:global_client) { instance_double(L1::Bitcoind::Client) }
  let(:harness) { instance_double(L1::RegtestHarness) }

  let(:peg_wallet) do
    instance_double(
      L1::UserWallet,
      wallet_name: "user_peg",
      identity_pubkey: "02peg",
      spendable_sats: 100_000_000,
      change_address: "bcrt1peg",
      client: peg_rpc
    )
  end

  let(:investor_wallet) do
    instance_double(
      L1::UserWallet,
      wallet_name: "user_inv",
      identity_pubkey: "02inv",
      spendable_sats: 100_000_000,
      change_address: "bcrt1invchg"
    )
  end

  let(:peg_rpc) { instance_double(L1::Bitcoind::Client) }
  let(:investor_rpc) { instance_double(L1::Bitcoind::Client) }

  let(:announcement) do
    Dlc::OracleClient::Announcement.new(
      event_id: "deal-#{budget.id}", oracle_pubkey: "02ab", nonces: %w[n0 n1],
      num_digits: 20, unit: "EUR/BTC", precision: 0, maturity_epoch: 123, hex: "annhex", raw: {}
    )
  end

  let(:contract) do
    Dlc::NodeClient::Contract.new(
      contract_id: "c-1", funding_txid: "ab" * 32, funding_vout: 0,
      funding_address: nil, funding_tx_hex: "0200000000", status: "pending_funding", raw: {}
    )
  end

  before do
    allow(oracle).to receive(:announce_numeric).and_return(announcement)
    allow(node).to receive(:create_contract).and_return(contract)

    allow(L1::UserWallet).to receive(:for) do |user|
      user == investor ? investor_wallet : peg_wallet
    end
    allow(peg_wallet).to receive(:select_coins).and_return(
      [{ "txid" => "aa" * 32, "vout" => 0, "amount" => 0.101 }]
    )
    allow(investor_wallet).to receive(:select_coins).and_return(
      [{ "txid" => "bb" * 32, "vout" => 1, "amount" => 0.101 }]
    )
    allow(investor_wallet).to receive(:receive_address).and_return("bcrt1invpay")

    allow(L1::Bitcoind::Client).to receive(:new).and_return(global_client)
    allow(peg_rpc).to receive(:call)
      .with("signrawtransactionwithwallet", "0200000000")
      .and_return("hex" => "signed_peg", "complete" => false)
    allow(investor_rpc).to receive(:call)
      .with("signrawtransactionwithwallet", "signed_peg")
      .and_return("hex" => "signed_both", "complete" => true)
    allow(investor_wallet).to receive(:client).and_return(investor_rpc)
    allow(global_client).to receive(:call).with("sendrawtransaction", "signed_both").and_return("ab" * 32)

    allow(L1::RegtestHarness).to receive(:new).and_return(harness)
    allow(harness).to receive(:mine_blocks)
  end

  it "announces the event, funds the contract from reserves and persists a DlcContract" do
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

  it "records the DLC funding as the collateral lock on the budget" do
    described_class.call(budget: budget, oracle: oracle, node: node)
    budget.reload

    expect(budget.l1_multisig_provisioned?).to be(true)
    expect(budget.escrow_outpoint).to eq("#{'ab' * 32}:0")
    expect(budget.peg_party_pubkey).to eq("02peg")
    expect(budget.investor_pubkey).to eq("02inv")
    expect(budget.recovery_package.dig("escrow", "outpoint")).to eq("#{'ab' * 32}:0")
  end

  it "signs the unsigned funding tx with both reserve wallets and broadcasts it" do
    described_class.call(budget: budget, oracle: oracle, node: node)

    expect(peg_rpc).to have_received(:call).with("signrawtransactionwithwallet", "0200000000")
    expect(investor_rpc).to have_received(:call).with("signrawtransactionwithwallet", "signed_peg")
    expect(global_client).to have_received(:call).with("sendrawtransaction", "signed_both")
    expect(harness).to have_received(:mine_blocks).with(1)
  end

  it "passes the reserve inputs, change and payout addresses to the node" do
    described_class.call(budget: budget, oracle: oracle, node: node)

    expect(node).to have_received(:create_contract) do |args|
      expect(args[:oracle_announcement]).to eq("annhex")
      expect(args[:peg_collateral_sats]).to eq(10_000_000)
      expect(args[:investor_collateral_sats]).to eq(10_000_000)
      expect(args[:refund_locktime]).to eq(budget.refund_locktime_height)
      expect(args[:peg_inputs]).to eq([{ txid: "aa" * 32, vout: 0, amount_sats: 10_100_000 }])
      expect(args[:investor_inputs]).to eq([{ txid: "bb" * 32, vout: 1, amount_sats: 10_100_000 }])
      expect(args[:peg_change_address]).to eq("bcrt1peg")
      expect(args[:investor_change_address]).to eq("bcrt1invchg")
      expect(args[:investor_payout_address]).to eq("bcrt1invpay")
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
