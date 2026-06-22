# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::InvestorYieldService do
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }
  let(:peg) { 60_000 }

  before do
    setup_active_budget!(borrower: alice, investor: bob, amount_eur_cents: 100_000, peg: peg)
  end

  it "does nothing when LTV is at or above 30%" do
    expect(described_class.call(budget: Budget.first)).to eq([])
  end

  it "pays BTC to the deal investor when LTV is below 30%" do
    budget = Budget.first
    MarketRate.current.update!(btc_eur_per_btc: 120_000)
    bob_savings_before = bob.btc_account.balance_sats

    results = described_class.call(budget: budget)

    expect(results.size).to eq(1)
    expect(results.first.user).to eq(bob)
    expect(budget.reload.loan_to_value_ratio(120_000)).to be_within(0.01).of(0.3)
    expect(bob.btc_account.reload.balance_sats).to be > bob_savings_before
    expect(budget.investor_yield_payouts.sum(:btc_sats)).to eq(results.sum(&:btc_sats))
    expect(budget.pool_sats).to eq(budget.borrower_locked_sats + budget.investor_locked_sats)
  end
end
