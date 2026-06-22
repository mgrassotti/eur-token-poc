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

  it "flags liquidation at 90% LTV" do
    budget = Budget.first

    expect(budget.liquidation_threshold_reached?(33_000)).to be(true)
  end
end
