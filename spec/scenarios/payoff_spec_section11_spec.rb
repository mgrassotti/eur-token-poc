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
    alice.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(amount_cents, strike))
    bob.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(amount_cents * 2, strike))
    MarketRate.current.update!(btc_eur_per_btc: strike)

    budget = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: amount_cents,
      period_start: period_start,
      period_end: period_end
    )
    budget.update!(rate_bps_monthly: rate_bps)
    Budgets::ActivateService.call(budget: budget, investor: bob)
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

  it "documents hedge ≥ 2× peg when investor locks double (§11)" do
    budget = activate_deal!
    expect(budget.peg_collateral_sats).to eq(budget.hedge_collateral_sats)
    expect(budget.hedge_collateral_meets_floor?).to be(false)

    budget.update!(investor_locked_sats: budget.peg_collateral_sats * 2)
    budget.collateral_lock.update!(amount_sats: budget.peg_collateral_sats * 3)

    expect(budget.hedge_collateral_meets_floor?).to be(true)
    expect(budget.hedge_collateral_sats).to eq(2 * budget.peg_collateral_sats)
  end

  it "conserves escrow sats (holders + investor + mining fee)" do
    budget = activate_deal!
    escrow = budget.pool_sats
    fee = Budget::ESTIMATED_SETTLEMENT_FEE_SATS

    result = Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: 50_000)

    total = result.payoff.total_holder_sats + result.investor_btc_sats + result.payoff.mining_fee_sats
    expect(total).to eq(escrow)
  end
end
