# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budget do
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }

  before do
    setup_active_budget!(borrower: alice, investor: bob, amount_eur_cents: 100_000, peg: 60_000)
  end

  it "computes LTV from minted tokens and pool value at current rate" do
    budget = Budget.first

    expect(budget.loan_to_value_ratio(60_000)).to be_within(0.01).of(0.5)
    expect(budget.liquidation_threshold_reached?(50_000)).to be(false)
  end

  it "flags margin call at 70% LTV and liquidation at 90%" do
    budget = Budget.first

    expect(budget.margin_call_threshold_reached?(40_000)).to be(true)
    expect(budget.liquidation_threshold_reached?(40_000)).to be(false)
    expect(budget.liquidation_threshold_reached?(33_000)).to be(true)
  end

  it "requires 2× opening collateral (1× richiedente + 1× investitore)" do
    budget = Budget.first

    expect(budget.opening_collateral_adequate?).to be(true)
    expect(budget.loan_to_value_ratio(60_000)).to be_within(0.01).of(0.5)
  end
end
