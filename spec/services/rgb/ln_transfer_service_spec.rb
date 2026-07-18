# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rgb::LnTransferService do
  let(:alice) { create(:user) }
  let(:claude) { create(:user) }
  let(:budget) { create(:budget, borrower: alice, rgb_asset_id: "rgb_stub", status: :active) }
  let(:sender) { instance_double(Rgb::LightningClient) }
  let(:recipient) { instance_double(Rgb::LightningClient) }

  before do
    allow(Rgb::BalanceService).to receive(:spendable).and_return(100_000)
    allow(Rgb::HubChannelService).to receive(:ensure_capacity!)
    allow(Rgb::Nodes).to receive(:for_user).with(alice).and_return(sender)
    allow(Rgb::Nodes).to receive(:for_user).with(claude).and_return(recipient)
    allow(recipient).to receive(:ln_invoice).and_return("invoice" => "lnbcrt1test")
    allow(sender).to receive(:send_payment).and_return(
      "payment_hash" => "abc123",
      "status" => "Pending"
    )
    allow(sender).to receive(:payments).and_return(
      [{ "payment_hash" => "abc123", "status" => "Succeeded" }]
    )
  end

  it "pays an LN asset invoice after ensuring hub capacity" do
    result = described_class.call(
      budget: budget,
      from_user: alice,
      to_user: claude,
      amount_cents: 25_000
    )

    expect(Rgb::HubChannelService).to have_received(:ensure_capacity!).with(
      from_user: alice,
      to_user: claude,
      asset_id: "rgb_stub",
      amount_cents: 25_000,
      budget: budget
    )
    expect(recipient).to have_received(:ln_invoice).with(
      asset_id: "rgb_stub",
      asset_amount: 25_000,
      expiry_sec: described_class::INVOICE_EXPIRY_SEC
    )
    expect(sender).to have_received(:send_payment).with(invoice: "lnbcrt1test")
    expect(result.txid).to eq("abc123")
    expect(result.recipient_id).to eq("lnbcrt1test")
    expect(result.amount).to eq(25_000)
  end
end
