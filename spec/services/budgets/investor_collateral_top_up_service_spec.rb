# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::InvestorCollateralTopUpService do
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }

  let!(:budget) do
    setup_active_budget!(borrower: alice, investor: bob, amount_eur_cents: 100_000, peg: 50_000)
  end

  before do
    MarketRate.current.update!(btc_eur_per_btc: 30_000)
    bob.btc_account.update!(balance_sats: 20_000_000)
  end

  it "adds sats to the deal pool and lowers LTV" do
    ltv_before = budget.loan_to_value_ratio(30_000)
    amount_sats = 5_000_000
    pool_before = budget.pool_sats

    described_class.call(budget: budget, investor: bob, amount_sats: amount_sats)

    budget.reload
    expect(budget.pool_sats).to eq(pool_before + amount_sats)
    expect(budget.investor_locked_sats).to eq(budget.collateral_sats_at_peg(50_000) + amount_sats)
    expect(budget.loan_to_value_ratio(30_000)).to be < ltv_before
  end

  it "rejects top-up from non-investor" do
    expect do
      described_class.call(budget: budget, investor: alice, amount_sats: 1_000_000)
    end.to raise_error(described_class::Error, "Solo l'investitore del deal può versare collateral aggiuntivo")
  end
end
