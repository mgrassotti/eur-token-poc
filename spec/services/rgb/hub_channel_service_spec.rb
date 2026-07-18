# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rgb::HubChannelService do
  let(:alice) { create(:user) }
  let(:claude) { create(:user) }
  let(:asset_id) { "rgb:test" }
  let(:sender) { instance_double(Rgb::LightningClient, base_url: "http://127.0.0.1:3001") }
  let(:recipient) { instance_double(Rgb::LightningClient, base_url: "http://127.0.0.1:3003") }
  let(:hub) { instance_double(Rgb::LightningClient, base_url: "http://127.0.0.1:3005") }

  before do
    allow(Rgb::WalletSetupService).to receive(:ensure_for!).with(alice).and_return(sender)
    allow(Rgb::WalletSetupService).to receive(:ensure_for!).with(claude).and_return(recipient)
    allow(Rgb::HubSetupService).to receive(:call).and_return(hub)
    allow(Rgb::Nodes).to receive(:for_user).with(claude).and_return(recipient)

    allow(sender).to receive(:asset_balance).with(asset_id: asset_id).and_return(
      "settled" => 200_000, "offchain_outbound" => 50_000, "offchain_inbound" => 0
    )
    allow(recipient).to receive(:asset_balance).with(asset_id: asset_id).and_return(
      "settled" => 0, "offchain_outbound" => 0, "offchain_inbound" => 50_000
    )
    allow(hub).to receive(:asset_balance).with(asset_id: asset_id).and_return(
      "settled" => 0, "offchain_outbound" => 0, "offchain_inbound" => 0
    )
  end

  it "is a no-op when both edges already have capacity" do
    expect(sender).not_to receive(:open_channel)
    expect(hub).not_to receive(:open_channel)
    expect(sender).not_to receive(:send_asset)

    result = described_class.ensure_capacity!(
      from_user: alice,
      to_user: claude,
      asset_id: asset_id,
      amount_cents: 40_000
    )

    expect(result[:sender_outbound]).to eq(50_000)
    expect(result[:recipient_inbound]).to eq(50_000)
  end
end
