# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rgb::BalanceService do
  let(:alice) { create(:user) }
  let(:budget) { create(:budget, borrower: alice, amount_eur_cents: 100_000) }

  it "reads from rgb_assignments when sidecar is unavailable" do
    allow(Rgb::SidecarClient.instance).to receive(:available?).and_return(false)
    RgbAssignment.create!(
      budget: budget,
      user: alice,
      assignment_id: SecureRandom.uuid,
      holder_pubkey: "02#{"a" * 64}",
      notional_share_cents: 75_000
    )

    expect(described_class.settled(user: alice, budget: budget)).to eq(75_000)
  end
end
