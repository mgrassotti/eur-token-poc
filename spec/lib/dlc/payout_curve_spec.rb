# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dlc::PayoutCurve do
  let(:fee) { Budget::ESTIMATED_SETTLEMENT_FEE_SATS }
  let(:pool_sats) { 20_000_000 }

  let(:budget) do
    b = create(
      :budget,
      amount_eur_cents: 500_000,
      collateral_eur_cents: 500_000,
      rate_bps_monthly: 100,
      peg_eur_per_btc: 50_000,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 7, 1)
    )
    CollateralLock.create!(budget: b, amount_sats: pool_sats, locked_at: Time.current)
    b
  end

  it "raises when the peg is not set" do
    budget.update!(peg_eur_per_btc: nil)
    expect { described_class.for(budget: budget) }.to raise_error(ArgumentError, /peg/)
  end

  it "samples FloorEUR splits across price anchors including the bounds" do
    points = described_class.for(budget: budget, num_digits: 20)
    max = Dlc::Numeric.max_value(num_digits: 20)

    expect(points).to all(be_a(described_class::Point))
    expect(points.map(&:outcome)).to eq(points.map(&:outcome).sort.uniq)
    expect(points.map(&:outcome)).to include(1, max)
  end

  it "conserves the distributable pot at every anchor (peg + investor == pool - fee)" do
    distributable = pool_sats - fee
    described_class.for(budget: budget, num_digits: 20).each do |point|
      expect(point.peg_sats + point.investor_sats).to eq(distributable)
    end
  end

  it "is monotonic: the peg pot does not grow as the price rises" do
    peg_sats = described_class.for(budget: budget, num_digits: 20).map(&:peg_sats)
    expect(peg_sats).to eq(peg_sats.sort.reverse)
  end

  it "caps the peg pot at the distributable amount for low prices" do
    points = described_class.for(budget: budget, num_digits: 20)
    expect(points.first.peg_sats).to eq(pool_sats - fee)
    expect(points.first.investor_sats).to eq(0)
  end
end
