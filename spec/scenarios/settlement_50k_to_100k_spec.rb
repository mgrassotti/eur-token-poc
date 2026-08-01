# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settlement scenario 50k → 100k (FloorEUR)" do
  let(:peg) { 50_000 }
  let(:end_rate) { 100_000 }
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:claude) { create(:user, name: "Claude") }
  let(:david) { create(:user, name: "David") }

  def six_month_period
    start = Date.new(2026, 1, 1)
    [start, start >> 6]
  end

  before do
    period_start, period_end = six_month_period
    alice.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(500_000, peg) + 10_000)
    bob.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(1_000_000, peg) + 10_000)
    claude.btc_account.update!(balance_sats: 0)
    david.btc_account.update!(balance_sats: 0)
    MarketRate.current.update!(btc_eur_per_btc: peg)

    @budget = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: 500_000,
      period_start: period_start,
      period_end: period_end
    )
    Budgets::ActivateService.call(budget: @budget, investor: bob)
    advance_to_maturity!(@budget)
    Tokens::TransferService.call(budget: @budget, from_user: alice, to_user: claude, amount_cents: 50_000)
    Tokens::TransferService.call(budget: @budget, from_user: claude, to_user: david, amount_cents: 25_000)
  end

  it "pays fixed € liability in fewer sats when spot doubles; investor keeps remainder" do
    result = Settlements::ExecuteService.call(budget: @budget, end_btc_eur_rate: end_rate)

    expect(result.payoff.liability_eur_cents).to eq(530_000)
    expect(result.payoff.total_holder_sats).to eq(5_300_000)
    expect(result.investor_btc_sats).to be > 0
    expect(result.borrower_btc_sats).to eq(0)
  end
end
