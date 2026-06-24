# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tokens::Spendable do
  let(:alice) { create(:user) }
  let(:budget) { create(:budget, borrower: alice, amount_eur_cents: 100_000, rgb_asset_id: "rgb1", status: :active) }

  before do
    RgbAssignment.create!(
      budget: budget,
      user: alice,
      assignment_id: SecureRandom.uuid,
      holder_pubkey: "02#{"a" * 64}",
      notional_share_cents: 60_000,
      rgb_asset_id: "rgb1"
    )
    TokenAccount.create!(user: alice, budget: budget, balance_cents: 40_000)
  end

  it "uses BalanceService settled amount per deal" do
    allow(Rgb::BalanceService).to receive(:settled).with(user: alice, budget: budget).and_return(60_000)

    positions = described_class.positions_for(alice)

    expect(positions.size).to eq(1)
    expect(positions.first.balance_cents).to eq(60_000)
    expect(positions.first.budget).to eq(budget)
  end

  it "sums RGB balances for total spendable" do
    allow(Rgb::BalanceService).to receive(:settled).and_return(60_000)

    expect(described_class.total_cents_for(alice)).to eq(60_000)
  end
end
