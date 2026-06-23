# frozen_string_literal: true

require "rails_helper"

RSpec.describe "L1 settlement on-chain payout", :regtest do
  def bitcoind_available?
    L1::Bitcoind::Client.new.available?
  end

  before do
    skip "Start regtest: docker compose -f docker-compose.regtest.yml up -d" unless bitcoind_available?
    ENV["L1_ENABLED"] = "1"
    L1::RegtestResetService.call
  end

  after do
    ENV.delete("L1_ENABLED")
  end

  it "settles on-chain and preserves investor reserve change" do
    alice = create(:user, name: "Alice", email: "alice-settle-#{SecureRandom.hex(4)}@example.com")
    bob = create(:user, name: "Bob", email: "bob-settle-#{SecureRandom.hex(4)}@example.com")
    claude = create(:user, name: "Claude", email: "claude-settle-#{SecureRandom.hex(4)}@example.com")

    L1::DepositReserveService.call(user: alice, amount_sats: 10_000_000)
    L1::DepositReserveService.call(user: bob, amount_sats: 25_000_000)

    MarketRate.current.update!(btc_eur_per_btc: 50_000)
    period_start = Date.new(2026, 1, 1)
    budget = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: 500_000,
      period_start: period_start,
      period_end: period_start >> 6
    )
    Budgets::ActivateService.call(budget: budget, investor: bob)
    budget.reload

    expect(budget.l1_multisig_provisioned?).to be(true)
    bob_reserve_after_funding = bob.btc_account.reload.balance_sats
    expect(bob_reserve_after_funding).to be_positive
    expect(bob_reserve_after_funding).to be < 25_000_000

    Tokens::TransferService.call(budget: budget, from_user: alice, to_user: claude, amount_cents: 100_000)
    advance_to_maturity!(budget)

    result = Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: 50_000)

    bob.reload
    expect(budget.reload).to be_settled
    expect(bob.btc_account.reload.balance_sats).to eq(bob_reserve_after_funding + result.investor_btc_sats)
    expect(claude.btc_account.reload.balance_sats).to eq(result.payouts.find { |p| p.user == claude }.btc_sats)
    expect(alice.btc_account.reload.balance_sats).to eq(result.payouts.find { |p| p.user == alice }.btc_sats)
  end
end
