# frozen_string_literal: true

require "rails_helper"

RSpec.describe L1::WalletInventoryService do
  let(:market_rate) { MarketRate.current.tap { |r| r.update!(btc_eur_per_btc: 50_000) } }
  let(:client) { instance_double(L1::Bitcoind::Client) }
  let(:exchange_client) { instance_double(L1::Bitcoind::Client) }
  let(:alice_client) { instance_double(L1::Bitcoind::Client) }

  before do
    allow(L1::Bitcoind::Client).to receive(:new).and_return(client)
    allow(client).to receive(:available?).and_return(true)
    allow(client).to receive(:call).with("listwallets").and_return(%w[l1_external_wallet user_2])
    allow(client).to receive(:with_wallet).with("l1_external_wallet").and_return(exchange_client)
    allow(client).to receive(:with_wallet).with("user_2").and_return(alice_client)
    allow(exchange_client).to receive(:call).with("getbalance", "*", 1).and_return(1.0)
    allow(alice_client).to receive(:call).with("listunspent", 1, 9_999_999).and_return(
      [{ "amount" => 0.02, "coinbase" => false }]
    )

    alice = create(:user, name: "Alice")
    alice.btc_account.update!(bitcoind_wallet_name: "user_2")
  end

  it "returns wallet rows with EUR equivalent at the current rate" do
    result = described_class.call(market_rate: market_rate)

    expect(result.available).to be(true)
    expect(result.rows.map(&:wallet_name)).to eq(%w[l1_external_wallet user_2])
    expect(result.rows.first.label).to eq(L1::ExchangeWallet::DISPLAY_NAME)
    expect(result.rows.first.sats).to eq(100_000_000)
    expect(result.rows.second.label).to eq("Alice")
    expect(result.rows.second.sats).to eq(2_000_000)
    expect(result.rows.second.eur).to be_within(0.01).of(1_000.0)
    expect(result.total_sats).to eq(102_000_000)
    expect(result.total_eur).to be_within(0.01).of(51_000.0)
  end

  it "returns unavailable when bitcoind is down" do
    allow(client).to receive(:available?).and_return(false)

    result = described_class.call(market_rate: market_rate)

    expect(result.available).to be(false)
    expect(result.error_message).to include("bitcoind regtest")
  end
end
