# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settlement scenario 50k → 100k" do
  let(:peg) { 50_000 }
  let(:end_rate) { 100_000 }
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:claude) { create(:user, name: "Claude") }
  let(:david) { create(:user, name: "David") }

  def savings_sats(user)
    user.btc_account.balance_sats
  end

  def savings_eur(user, rate)
    BtcConversion.sats_to_eur(savings_sats(user), rate)
  end

  def total_wealth_eur(user, rate)
    spending_cents = user.token_accounts.joins(:budget).merge(Budget.active).sum(:balance_cents)
    investment_sats = user.invested_budgets.active.sum(:investor_locked_sats)
    savings_eur(user, rate) +
      BtcConversion.sats_to_eur(investment_sats, rate) +
      (spending_cents / 100.0)
  end

  before do
    alice.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(500_000, peg))
    bob.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(1_000_000, peg))
    claude.btc_account.update!(balance_sats: 0)
    david.btc_account.update!(balance_sats: 0)
    MarketRate.current.update!(btc_eur_per_btc: peg)
  end

  it "credits the FX surplus to the investor when the end rate is above peg" do
    budget = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: 100_000,
      period_start: Date.current,
      period_end: Date.current + 1.month
    )
    Budgets::ActivateService.call(budget: budget, investor: bob)

    Tokens::TransferService.call(budget: budget, from_user: alice, to_user: claude, amount_cents: 10_000)
    Tokens::TransferService.call(budget: budget, from_user: claude, to_user: david, amount_cents: 5_000)

    MarketRate.current.update!(btc_eur_per_btc: end_rate)

    expect(savings_eur(alice, end_rate)).to be_within(0.01).of(8_000)
    expect(total_wealth_eur(alice, end_rate)).to be_within(0.01).of(8_900)
    expect(savings_eur(bob, end_rate)).to be_within(0.01).of(16_000)
    expect(total_wealth_eur(bob, end_rate)).to be_within(0.01).of(20_000)

    result = Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: end_rate)

    expect(savings_eur(alice.reload, end_rate)).to be_within(0.01).of(8_900)
    expect(savings_eur(bob.reload, end_rate)).to be_within(0.01).of(21_000)
    expect(savings_eur(claude.reload, end_rate)).to be_within(0.01).of(50)
    expect(savings_eur(david.reload, end_rate)).to be_within(0.01).of(50)
    expect(result.investor_btc_sats).to eq(5_000_000)
    expect(result.borrower_btc_sats).to eq(0)
    expect(result.total_fx_to_investor_sats).to eq(1_000_000)
  end
end
