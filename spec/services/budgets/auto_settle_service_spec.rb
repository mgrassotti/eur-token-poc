# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::AutoSettleService do
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }

  before do
    create(:user, :admin, email: "admin@example.com")
    @budget = setup_active_budget!(borrower: alice, investor: bob, amount_eur_cents: 100_000, peg: 60_000, block_height: 0)
  end

  it "settles active deals when the block reaches maturity" do
    ChainState.update_block_height!(@budget.maturity_block_height)

    expect(@budget.reload).to be_settled
    expect(Settlement.count).to eq(1)
  end

  it "does nothing before maturity block" do
    ChainState.update_block_height!(@budget.maturity_block_height - 1)

    expect(@budget.reload).to be_active
    expect(Settlement.count).to eq(0)
  end
end
