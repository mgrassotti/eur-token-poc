# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rgb::BalanceService, skip: "MVP savings: RGB unplugged" do
  let(:alice) { create(:user) }
  let(:budget) { create(:budget, borrower: alice, amount_eur_cents: 100_000) }

  it "reads from rgb_assignments when the RGB node is unavailable" do
    allow(Rgb::Nodes).to receive(:available_for?).with(alice).and_return(false)
    RgbAssignment.create!(
      budget: budget,
      user: alice,
      assignment_id: SecureRandom.uuid,
      holder_pubkey: "02#{"a" * 64}",
      notional_share_cents: 75_000
    )

    expect(described_class.settled(user: alice, budget: budget)).to eq(75_000)
  end

  it "returns zero when the node no longer knows the contract" do
    budget.update!(rgb_asset_id: "rgb:stale")
    RgbAssignment.create!(
      budget: budget,
      user: alice,
      assignment_id: SecureRandom.uuid,
      holder_pubkey: "02#{"a" * 64}",
      notional_share_cents: 50_000
    )
    client = instance_double(Rgb::LightningClient)
    allow(Rgb::Nodes).to receive(:available_for?).with(alice).and_return(true)
    allow(Rgb::Nodes).to receive(:for_user).with(alice).and_return(client)
    allow(client).to receive(:asset_balance)
      .with(asset_id: "rgb:stale")
      .and_raise(Rgb::LightningClient::Error, "Unknown RGB contract ID")

    expect(described_class.settled(user: alice, budget: budget)).to eq(0)
  end
end
