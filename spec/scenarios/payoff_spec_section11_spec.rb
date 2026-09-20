# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PAYOFF-SPEC §11 integration" do
  let(:strike) { 50_000 }
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:claude) { create(:user, name: "Claude") }

  def six_month_period
    start = Date.new(2026, 1, 1)
    [start, start >> 6]
  end

  def activate_deal!(amount_cents: 500_000, rate_bps: 100)
    period_start, period_end = six_month_period
    alice.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(amount_cents, strike) + 10_000)
    bob.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(amount_cents * 2, strike) + 10_000)
    MarketRate.current.update!(btc_eur_per_btc: strike)

    budget = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: amount_cents,
      period_start: period_start,
      period_end: period_end
    )
    budget.update!(rate_bps_monthly: rate_bps)
    unit_activate_budget!(budget, investor: bob)
    budget.reload
    advance_to_maturity!(budget)
    budget
  end

  it "settles with FloorEUR liability at three spots (§5)" do
    {
      50_000 => 10_600_000,
      100_000 => 5_300_000
    }.each do |spot, expected_holder_sats|
      test_budget = activate_deal!
      result = Settlements::ExecuteService.call(budget: test_budget, end_btc_eur_rate: spot)

      expect(result.payoff.liability_eur_cents).to eq(530_000)
      expect(result.payoff.total_holder_sats).to eq(expected_holder_sats)
    end

    test_budget = activate_deal!
    fee = Budget::ESTIMATED_SETTLEMENT_FEE_SATS
    result = Settlements::ExecuteService.call(budget: test_budget, end_btc_eur_rate: 25_000)

    expect(result.payoff.gross_holder_sats).to eq(21_200_000)
    expect(result.payoff.insolvent).to be(true)
    expect(result.payoff.total_holder_sats).to eq(test_budget.pool_sats - fee)
  end

  it "pro-rates after 40% token transfer (§5)" do
    budget = activate_deal!
    Tokens::TransferService.call(budget: budget, from_user: alice, to_user: claude, amount_cents: 200_000)

    result = Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: 50_000)
    alice_payout = result.payouts.find { |p| p.user == alice }
    claude_payout = result.payouts.find { |p| p.user == claude }

    expect(result.payoff.total_holder_sats).to eq(10_600_000)
    expect(alice_payout.btc_sats).to eq(6_360_000)
    expect(claude_payout.btc_sats).to eq(4_240_000)
  end

  it "documents 2× opening collateral at activation (§11)" do
    budget = activate_deal!

    expect(budget.opening_collateral_adequate?).to be(true)
    expect(budget.pool_sats).to eq(budget.opening_collateral_sats_at_peg(budget.peg_eur_per_btc))
    expect(budget.loan_to_value_ratio(budget.peg_eur_per_btc)).to be_within(0.01).of(0.5)
  end

  it "conserves escrow sats (holders + investor + mining fee + distribution fee)" do
    budget = activate_deal!
    escrow = budget.pool_sats
    fee = Budget::ESTIMATED_SETTLEMENT_FEE_SATS
    holder_count = budget.token_accounts.where("balance_cents > 0").count
    dist_fee = Dlc::Distribution.fee_estimate(holder_count)

    result = Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: 50_000)

    total = result.payouts.sum(&:btc_sats) + result.investor_btc_sats + result.payoff.mining_fee_sats + dist_fee
    expect(total).to eq(escrow)
  end
end
