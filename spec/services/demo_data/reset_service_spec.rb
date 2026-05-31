# frozen_string_literal: true

require "rails_helper"

RSpec.describe DemoData::ResetService do
  let!(:admin) { create(:user, :admin, email: "admin@example.com", name: "Admin") }
  let!(:alice) { create(:user, email: "alice@example.com", name: "Alice") }
  let!(:bob) { create(:user, email: "bob@example.com", name: "Bob") }
  let!(:claude) { create(:user, email: "claude@example.com", name: "Claude") }

  before do
    alice.btc_account.update!(balance_sats: 10_000_000)
    bob.btc_account.update!(balance_sats: 5_000_000)
    MarketRate.current.update!(btc_eur_per_btc: 60_000)
    budget = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: 100_000,
      period_start: Date.current,
      period_end: Date.current + 1.month
    )
    Budgets::ActivateService.call(budget: budget, investor: bob)
  end

  it "clears ledger and sets demo balances" do
    described_class.call

    expect(Budget.count).to eq(0)
    expect(Settlement.count).to eq(0)
    expect(TokenAccount.count).to eq(0)

    expect(alice.btc_account.reload.balance_sats).to eq(10_000_000)
    expect(bob.btc_account.reload.balance_sats).to eq(20_000_000)
    expect(claude.btc_account.reload.balance_sats).to eq(0)
    expect(admin.btc_account.reload.balance_sats).to eq(0)
    expect(MarketRate.current.btc_eur_per_btc).to eq(60_000)
  end

  it "creates demo users when they are missing" do
    Settlement.delete_all
    TokenTransfer.delete_all
    TokenAccount.delete_all
    CollateralLock.delete_all
    Budget.delete_all
    MarketRate.update_all(set_by_id: nil)
    BtcAccount.delete_all
    User.delete_all

    described_class.call

    expect(User.count).to eq(DemoData::ResetService::DEMO_USERS.size)
    expect(User.find_by!(email: "alice@example.com").btc_account.balance_sats).to eq(10_000_000)
  end
end
