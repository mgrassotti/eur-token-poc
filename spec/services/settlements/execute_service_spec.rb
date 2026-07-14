# frozen_string_literal: true

require "rails_helper"

RSpec.describe Settlements::ExecuteService do
  let(:peg) { 50_000 }
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:claude) { create(:user, name: "Claude") }
  let(:david) { create(:user, name: "David") }

  def six_month_period
    start = Date.new(2026, 1, 1)
    [start, start >> 6]
  end

  let!(:budget) do
    period_start, period_end = six_month_period
    alice.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(500_000, peg))
    bob.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(1_000_000, peg))
    MarketRate.current.update!(btc_eur_per_btc: peg)
    created = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: 500_000,
      period_start: period_start,
      period_end: period_end
    )
    Budgets::ActivateService.call(budget: created, investor: bob)
    created
  end

  before do
    Tokens::TransferService.call(budget: budget, from_user: alice, to_user: claude, amount_cents: 100_000)
    Tokens::TransferService.call(budget: budget, from_user: claude, to_user: david, amount_cents: 50_000)
    advance_to_maturity!(budget)
  end

  it "pays holders FloorEUR liability at spot and returns investor remainder" do
    end_rate = 50_000
    collateral_sats = budget.collateral_lock.amount_sats
    fee = Budget::ESTIMATED_SETTLEMENT_FEE_SATS
    dist_fee = Dlc::Distribution.fee_estimate(3)
    expected_total_holder = 10_600_000

    result = described_class.call(budget: budget, end_btc_eur_rate: end_rate)

    expect(result.payoff.liability_eur_cents).to eq(530_000)
    expect(result.payoff.total_holder_sats).to eq(expected_total_holder)
    expect(result.payouts.sum(&:btc_sats)).to eq(expected_total_holder)
    expect(result.investor_btc_sats).to eq(collateral_sats - expected_total_holder - fee - dist_fee)
    expect(budget.reload).to be_settled
  end

  it "returns more collateral to investor when spot is above strike (same € liability)" do
    low_spot_result = described_class.call(
      budget: activate_fresh_budget,
      end_btc_eur_rate: 50_000
    )
    high_spot_result = described_class.call(
      budget: activate_fresh_budget,
      end_btc_eur_rate: 100_000
    )

    expect(low_spot_result.payoff.total_holder_sats).to eq(10_600_000)
    expect(high_spot_result.payoff.total_holder_sats).to eq(5_300_000)
    expect(high_spot_result.investor_btc_sats).to be > low_spot_result.investor_btc_sats
  end

  it "conserves sats regardless of end rate" do
    [25_000, 50_000, 100_000].each do |end_rate|
      test_budget = activate_fresh_budget
      escrow = test_budget.collateral_lock.amount_sats
      fee = Budget::ESTIMATED_SETTLEMENT_FEE_SATS
      holder_count = test_budget.token_accounts.where("balance_cents > 0").count
      dist_fee = Dlc::Distribution.fee_estimate(holder_count)

      result = described_class.call(budget: test_budget, end_btc_eur_rate: end_rate)
      total = result.payouts.sum(&:btc_sats) + result.investor_btc_sats + fee + dist_fee
      expect(total).to eq(escrow)
    end
  end

  it "rejects settlement before maturity block" do
    ChainState.update_block_height!(budget.maturity_block_height - 1, auto_settle: false)

    expect do
      described_class.call(budget: budget, end_btc_eur_rate: peg)
    end.to raise_error(Settlements::ExecuteService::Error, /Settlement disponibile dal blocco/)
  end

  it "rejects inactive budgets" do
    expect do
      described_class.call(budget: create(:budget, borrower: alice), end_btc_eur_rate: 60_000)
    end.to raise_error(Settlements::ExecuteService::Error, I18n.t("services.settlements.execute.budget_not_active"))
  end

  it "updates the dashboard market rate when the end rate differs" do
    admin = create(:user, :admin)
    MarketRate.current.update!(btc_eur_per_btc: peg)

    result = described_class.call(budget: budget, end_btc_eur_rate: 25_000, set_by: admin)

    expect(result.market_rate_updated).to be(true)
    expect(MarketRate.current.btc_eur_per_btc).to eq(25_000)
    expect(MarketRate.current.set_by).to eq(admin)
  end

  it "does not update the dashboard market rate when the end rate is unchanged" do
    admin = create(:user, :admin)
    MarketRate.current.update!(btc_eur_per_btc: peg, set_by: admin)

    result = described_class.call(budget: budget, end_btc_eur_rate: peg, set_by: admin)

    expect(result.market_rate_updated).to be(false)
    expect(MarketRate.current.btc_eur_per_btc).to eq(peg)
  end

  def activate_fresh_budget
    period_start, period_end = six_month_period
    bob.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(1_000_000, peg))
    alice.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(500_000, peg))
    MarketRate.current.update!(btc_eur_per_btc: peg)
    created = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: 500_000,
      period_start: period_start,
      period_end: period_end
    )
    Budgets::ActivateService.call(budget: created, investor: bob)
    advance_to_maturity!(created)
    created
  end
end
