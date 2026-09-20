# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rgb::RedeemService, skip: "MVP savings: RGB unplugged" do
  let(:holder) { create(:user) }
  let(:budget) { create(:budget, borrower: holder, amount_eur_cents: 100_000, rgb_asset_id: "rgb_stub") }
  let(:holder_node) { instance_double(Rgb::LightningClient) }
  let(:issuer_node) { instance_double(Rgb::LightningClient) }

  before do
    allow(Rgb::Nodes).to receive(:issuer).and_return(issuer_node)
    allow(issuer_node).to receive(:init)
    allow(issuer_node).to receive(:unlock)
    allow(issuer_node).to receive(:create_utxos)
    allow(issuer_node).to receive(:refresh_transfers)
    # Keep the unit spec offline: no regtest funding/mining.
    allow(Rgb::NodeConfirm).to receive(:regtest?).and_return(false)
    allow(Rgb::NodeConfirm).to receive(:mine!)
    allow(Rgb::NodeConfirm).to receive(:settle_clients!)
  end

  it "skips when the deal has no RGB asset" do
    budget.update!(rgb_asset_id: nil)
    allow(Rgb::Nodes).to receive(:available_for?).with(holder).and_return(true)
    allow(holder_node).to receive(:send_asset)

    result = described_class.call(budget: budget, holder: holder)

    expect(result.status).to eq(:skipped)
    expect(holder_node).not_to have_received(:send_asset)
  end

  it "skips when the holder's node is unavailable" do
    allow(Rgb::Nodes).to receive(:available_for?).with(holder).and_return(false)

    result = described_class.call(budget: budget, holder: holder)

    expect(result.status).to eq(:skipped)
  end

  it "is a no-op when the holder RGB balance is zero" do
    allow(Rgb::Nodes).to receive(:available_for?).with(holder).and_return(true)
    allow(Rgb::BalanceService).to receive(:settled).and_return(0)

    result = described_class.call(budget: budget, holder: holder)

    expect(result.status).to eq(:empty)
  end

  it "drains the holder RGB balance to the issuer/treasury node" do
    allow(Rgb::Nodes).to receive(:available_for?).with(holder).and_return(true)
    allow(Rgb::BalanceService).to receive(:settled).and_return(40_000)
    allow(Rgb::WalletSetupService).to receive(:ensure_for!).with(holder).and_return(holder_node)
    allow(issuer_node).to receive(:rgb_invoice).and_return("recipient_id" => "rcp_issuer", "invoice" => "rgb:...")
    allow(holder_node).to receive(:send_asset).and_return("txid" => "redeem_txid")

    result = described_class.call(budget: budget, holder: holder)

    expect(result).to have_attributes(status: :redeemed, amount_cents: 40_000, txid: "redeem_txid")
    expect(issuer_node).to have_received(:rgb_invoice).with(amount: 40_000)
    expect(holder_node).to have_received(:send_asset).with(
      hash_including(asset_id: "rgb_stub", amount: 40_000, recipient_id: "rcp_issuer")
    )
  end
end
