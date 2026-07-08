# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dlc::NodeClient do
  subject(:client) { described_class.new(base_url: "http://ddk.test:8090") }

  let(:http) { instance_spy("Net::HTTP") }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
  end

  def ok(json)
    res = Net::HTTPOK.new("1.1", "200", "OK")
    res.instance_variable_set(:@body, JSON.generate(json))
    res.instance_variable_set(:@read, true)
    res
  end

  def bad(json, code = "400")
    res = Net::HTTPBadRequest.new("1.1", code, "Bad Request")
    res.instance_variable_set(:@body, JSON.generate(json))
    res.instance_variable_set(:@read, true)
    res
  end

  it "raises without a base_url" do
    expect { described_class.new(base_url: "") }.to raise_error(described_class::Error)
  end

  it "builds an unsigned 2-of-2 funding tx from the reserve inputs" do
    allow(http).to receive(:post) do |path, body, _headers|
      expect(path).to eq("/contracts")
      payload = JSON.parse(body)
      expect(payload["oracle_announcement"]).to eq("annhex")
      expect(payload["offer_collateral_sats"]).to eq(10_000_000)
      expect(payload["accept_collateral_sats"]).to eq(10_000_000)
      expect(payload["refund_locktime"]).to eq(2008)
      expect(payload["payouts"]).to eq([{ "outcome" => 50_000, "peg_sats" => 1, "investor_sats" => 2 }])
      expect(payload["peg_inputs"]).to eq([{ "txid" => "aa" * 32, "vout" => 0, "amount_sats" => 10_100_000 }])
      expect(payload["investor_inputs"]).to eq([{ "txid" => "bb" * 32, "vout" => 1, "amount_sats" => 10_100_000 }])
      expect(payload["peg_change_address"]).to eq("bcrt1peg")
      expect(payload["investor_change_address"]).to eq("bcrt1invchg")
      expect(payload["investor_payout_address"]).to eq("bcrt1invpay")
      ok(
        "contract_id" => "c-1",
        "funding_txid" => "ab" * 32,
        "funding_vout" => 0,
        "funding_tx_hex" => "0200000000",
        "status" => "pending_funding"
      )
    end

    contract = client.create_contract(
      oracle_announcement: "annhex",
      payouts: [{ outcome: 50_000, peg_sats: 1, investor_sats: 2 }],
      peg_collateral_sats: 10_000_000,
      investor_collateral_sats: 10_000_000,
      refund_locktime: 2008,
      peg_inputs: [{ txid: "aa" * 32, vout: 0, amount_sats: 10_100_000 }],
      investor_inputs: [{ txid: "bb" * 32, vout: 1, amount_sats: 10_100_000 }],
      peg_change_address: "bcrt1peg",
      investor_change_address: "bcrt1invchg",
      investor_payout_address: "bcrt1invpay"
    )

    expect(contract).to be_a(described_class::Contract)
    expect(contract.contract_id).to eq("c-1")
    expect(contract.funding_vout).to eq(0)
    expect(contract.funding_tx_hex).to eq("0200000000")
    expect(contract.status).to eq("pending_funding")
  end

  it "executes the CET for a given attestation" do
    allow(http).to receive(:post) do |path, body, _headers|
      expect(path).to eq("/contracts/c-1/execute")
      expect(JSON.parse(body)).to eq("attestation" => "atthex")
      ok(
        "cet_txid" => "cd" * 32,
        "outcome" => 60_000,
        "peg_sats" => 8_000_000,
        "investor_sats" => 12_000_000
      )
    end

    execution = client.execute_contract(contract_id: "c-1", attestation: "atthex")

    expect(execution).to be_a(described_class::Execution)
    expect(execution.cet_txid).to eq("cd" * 32)
    expect(execution.outcome).to eq(60_000)
    expect(execution.peg_sats).to eq(8_000_000)
    expect(execution.investor_sats).to eq(12_000_000)
  end

  it "fans out the peg_pot to holders via /distribute" do
    allow(http).to receive(:post) do |path, body, _headers|
      expect(path).to eq("/contracts/c-1/distribute")
      payload = JSON.parse(body)
      expect(payload["payouts"]).to eq(
        [{ "address" => "bcrt1a", "sats" => 600 }, { "address" => "bcrt1b", "sats" => 400 }]
      )
      ok(
        "txid" => "12" * 32,
        "payouts" => payload["payouts"],
        "investor_payout_sats" => 987,
        "investor_payout_address" => "bcrt1invpay"
      )
    end

    result = client.distribute(
      contract_id: "c-1",
      payouts: [{ address: "bcrt1a", sats: 600 }, { address: "bcrt1b", sats: 400 }]
    )

    expect(result).to be_a(described_class::DistributionResult)
    expect(result.txid).to eq("12" * 32)
    expect(result.investor_payout_sats).to eq(987)
    expect(result.investor_payout_address).to eq("bcrt1invpay")
  end

  it "broadcasts the timelocked refund" do
    allow(http).to receive(:post) do |path, _body, _headers|
      expect(path).to eq("/contracts/c-1/refund")
      ok("refund_txid" => "ef" * 32)
    end

    expect(client.refund_contract(contract_id: "c-1").refund_txid).to eq("ef" * 32)
  end

  it "reports availability from /info" do
    allow(http).to receive(:get).and_return(ok("pubkey" => "02abc", "network" => "regtest"))
    expect(client.available?).to be(true)
  end

  it "reports unavailable when the node is unreachable" do
    allow(http).to receive(:get).and_raise(Errno::ECONNREFUSED)
    expect(client.available?).to be(false)
  end

  it "raises a descriptive error on a non-success response" do
    allow(http).to receive(:post).and_return(bad("error" => "insufficient funds"))

    expect do
      client.create_contract(
        oracle_announcement: "x", payouts: [], peg_collateral_sats: 1,
        investor_collateral_sats: 1, refund_locktime: 1,
        peg_inputs: [{ txid: "aa" * 32, vout: 0, amount_sats: 2 }],
        investor_inputs: [{ txid: "bb" * 32, vout: 0, amount_sats: 2 }],
        peg_change_address: "a", investor_change_address: "b", investor_payout_address: "c"
      )
    end.to raise_error(described_class::Error, /insufficient funds/)
  end
end
