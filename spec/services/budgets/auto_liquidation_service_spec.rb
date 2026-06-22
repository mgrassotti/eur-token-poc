# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::AutoLiquidationService do
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:admin) { create(:user, :admin) }
  let(:peg) { 60_000 }

  before do
    setup_active_budget!(borrower: alice, investor: bob, amount_eur_cents: 100_000, peg: peg)
  end

  it "does nothing when LTV is below the threshold" do
    MarketRate.current.update!(btc_eur_per_btc: 50_000)

    results = described_class.call(set_by: admin)

    expect(results).to be_empty
    expect(Budget.first).to be_active
    expect(Settlement.count).to eq(0)
  end

  it "settles the deal when LTV reaches 90%" do
    MarketRate.current.update!(btc_eur_per_btc: 33_000)

    results = described_class.call(set_by: admin)

    expect(results.size).to eq(1)
    expect(Budget.first).to be_settled
    expect(alice.token_accounts.sum(:balance_cents)).to eq(0)
    expect(alice.btc_account.reload.balance_sats).to be_positive
  end
end
