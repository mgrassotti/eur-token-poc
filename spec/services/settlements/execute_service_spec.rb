# frozen_string_literal: true

require "rails_helper"

RSpec.describe Settlements::ExecuteService do
  let(:peg) { 60_000 }
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:claude) { create(:user, name: "Claude") }
  let(:david) { create(:user, name: "David") }

  let!(:budget) do
    bob.btc_account.update!(balance_sats: 5_000_000)
    alice.btc_account.update!(balance_sats: 10_000_000)
    MarketRate.current.update!(btc_eur_per_btc: peg)
    created = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: 100_000,
      period_start: Date.current,
      period_end: Date.current + 1.month
    )
    Budgets::ActivateService.call(budget: created, investor: bob)
    created
  end

  before do
    Tokens::TransferService.call(budget: budget, from_user: alice, to_user: claude, amount_cents: 30_000)
    Tokens::TransferService.call(budget: budget, from_user: claude, to_user: david, amount_cents: 10_000)
  end

  def expected_holder_sats(token_cents, end_rate)
    BtcConversion.settlement_holder_sats(token_cents, peg, end_rate).first
  end

  it "pays holders at end rate and returns remaining investor collateral" do
    end_rate = 50_000
    collateral_sats = budget.collateral_lock.amount_sats
    token_balances = { alice => 70_000, claude => 20_000, david => 10_000 }
    expected_holders_sats = token_balances.sum { |_, cents| expected_holder_sats(cents, end_rate) }

    result = described_class.call(budget: budget, end_btc_eur_rate: end_rate)

    expect(result.payouts.map(&:user)).to contain_exactly(alice, claude, david)
    token_balances.each do |user, token_cents|
      payout = result.payouts.find { |p| p.user == user }
      expect(payout.btc_sats).to eq(expected_holder_sats(token_cents, end_rate))
    end

    expect(result.settlement.total_btc_to_holders_sats).to eq(expected_holders_sats)
    expect(result.investor_btc_sats).to eq(collateral_sats - expected_holders_sats - budget.borrower_locked_sats)
    expect(budget.reload).to be_settled
  end

  it "returns more collateral to investor when end rate is above peg" do
    end_rate = 70_000
    collateral_sats = budget.collateral_lock.amount_sats
    expected_holders_sats = BtcConversion.token_cents_to_sats(100_000, end_rate)
    expected_fx_sats = BtcConversion.token_cents_to_sats(100_000, peg) - expected_holders_sats

    result = described_class.call(budget: budget, end_btc_eur_rate: end_rate)

    expect(result.settlement.total_btc_to_holders_sats).to eq(expected_holders_sats)
    expect(result.total_fx_to_investor_sats).to eq(expected_fx_sats)
    expect(result.investor_btc_sats).to eq(budget.investor_locked_sats + expected_fx_sats)
    expect(result.borrower_btc_sats).to eq(0)
  end

  it "returns all collateral to investor when end rate equals peg" do
    end_rate = peg
    collateral_sats = budget.collateral_lock.amount_sats
    expected_holders_sats = BtcConversion.token_cents_to_sats(100_000, end_rate)

    result = described_class.call(budget: budget, end_btc_eur_rate: end_rate)

    expect(result.total_fx_to_investor_sats).to eq(0)
    expect(result.settlement.total_btc_to_holders_sats).to eq(expected_holders_sats)
    expect(result.investor_btc_sats).to eq(collateral_sats - expected_holders_sats - budget.borrower_locked_sats)
    expect(collateral_sats).to eq(
      result.settlement.total_btc_to_holders_sats + result.borrower_btc_sats + result.settlement.btc_to_investor_sats
    )
  end

  it "conserves sats regardless of end rate" do
    [50_000, 60_000, 70_000].each do |end_rate|
      bob.btc_account.update!(balance_sats: 5_000_000)
      alice.btc_account.update!(balance_sats: 10_000_000)
      MarketRate.current.update!(btc_eur_per_btc: peg)
      test_budget = Budgets::CreateService.call(
        borrower: alice,
        amount_eur_cents: 100_000,
        period_start: Date.current,
        period_end: Date.current + 1.month
      )
      Budgets::ActivateService.call(budget: test_budget, investor: bob)

      result = described_class.call(budget: test_budget, end_btc_eur_rate: end_rate)
      total = result.settlement.total_btc_to_holders_sats + result.borrower_btc_sats + result.settlement.btc_to_investor_sats
      expect(total).to eq(test_budget.collateral_lock.amount_sats)
    end
  end

  it "rejects inactive budgets" do
    expect do
      described_class.call(budget: create(:budget, borrower: alice), end_btc_eur_rate: 60_000)
    end.to raise_error(Settlements::ExecuteService::Error, "Budget is not active")
  end

  it "updates the dashboard market rate when the end rate differs" do
    admin = create(:user, :admin)
    MarketRate.current.update!(btc_eur_per_btc: 60_000)

    result = described_class.call(budget: budget, end_btc_eur_rate: 50_000, set_by: admin)

    expect(result.market_rate_updated).to be(true)
    expect(MarketRate.current.btc_eur_per_btc).to eq(50_000)
    expect(MarketRate.current.set_by).to eq(admin)
  end

  it "does not update the dashboard market rate when the end rate is unchanged" do
    admin = create(:user, :admin)
    MarketRate.current.update!(btc_eur_per_btc: 60_000, set_by: admin)

    result = described_class.call(budget: budget, end_btc_eur_rate: 60_000, set_by: admin)

    expect(result.market_rate_updated).to be(false)
    expect(MarketRate.current.btc_eur_per_btc).to eq(60_000)
  end
end
