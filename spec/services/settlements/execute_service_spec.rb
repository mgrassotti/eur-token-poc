# frozen_string_literal: true

require "rails_helper"

RSpec.describe Settlements::ExecuteService do
  let(:peg) { 60_000 }
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:claude) { create(:user, name: "Claude") }
  let(:david) { create(:user, name: "David") }

  let!(:budget) do
    create(:budget, borrower: alice, amount_eur_cents: 100_000, collateral_eur_cents: 200_000)
  end

  before do
    bob.btc_account.update!(balance_sats: 5_000_000)
    Budgets::ActivateService.call(budget: budget, investor: bob, peg_eur_per_btc: peg)

    Tokens::TransferService.call(budget: budget, from_user: alice, to_user: claude, amount_cents: 30_000)
    Tokens::TransferService.call(budget: budget, from_user: claude, to_user: david, amount_cents: 10_000)
  end

  def holder_sats(user)
    BtcConversion.token_cents_to_sats(user.token_accounts.find_by!(budget: budget).balance_cents, peg)
  end

  it "distributes BTC at peg and returns remainder to investor" do
    collateral_sats = budget.collateral_lock.amount_sats
    expected_holders_sats = BtcConversion.token_cents_to_sats(100_000, peg)

    result = described_class.call(budget: budget, end_btc_eur_rate: 70_000)

    expect(result.payouts.map(&:user)).to contain_exactly(alice, claude, david)
    expect(holder_sats(alice)).to eq(0) # balances burned
    expect(result.settlement.total_btc_to_holders_sats).to eq(expected_holders_sats)
    expect(result.investor_btc_sats).to eq(collateral_sats - expected_holders_sats)
    expect(collateral_sats).to eq(result.settlement.total_btc_to_holders_sats + result.settlement.btc_to_investor_sats)
    expect(budget.reload).to be_settled
  end

  it "conserves sats regardless of end rate" do
    collateral_sats = budget.collateral_lock.amount_sats

    [50_000, 60_000, 70_000].each do |end_rate|
      test_budget = create(:budget, borrower: alice, amount_eur_cents: 100_000, collateral_eur_cents: 200_000)
      bob.btc_account.update!(balance_sats: 5_000_000)
      Budgets::ActivateService.call(budget: test_budget, investor: bob, peg_eur_per_btc: peg)

      result = described_class.call(budget: test_budget, end_btc_eur_rate: end_rate)
      total = result.settlement.total_btc_to_holders_sats + result.settlement.btc_to_investor_sats
      expect(total).to eq(test_budget.collateral_lock.amount_sats)
    end
  end

  it "rejects inactive budgets" do
    expect do
      described_class.call(budget: create(:budget, borrower: alice), end_btc_eur_rate: 60_000)
    end.to raise_error(Settlements::ExecuteService::Error, "Budget is not active")
  end
end
