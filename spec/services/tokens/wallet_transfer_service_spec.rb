# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tokens::WalletTransferService do
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:claude) { create(:user, name: "Claude") }

  def create_active_budget!(borrower:, investor:, amount_cents:, peg: 60_000)
    borrower.btc_account.update!(balance_sats: 10_000_000)
    investor.btc_account.update!(balance_sats: 10_000_000)
    MarketRate.current.update!(btc_eur_per_btc: peg)
    budget = Budgets::CreateService.call(
      borrower: borrower,
      amount_eur_cents: amount_cents,
      period_start: Date.current,
      period_end: Date.current + 6.months
    )
    Budgets::ActivateService.call(budget: budget, investor: investor)
    budget
  end

  it "uses a single deal when it has enough balance" do
    budget = create_active_budget!(borrower: alice, investor: bob, amount_cents: 100_000)

    parts = described_class.call(from_user: alice, to_user: claude, amount_cents: 40_000)

    expect(parts).to eq([described_class::TransferPart.new(budget: budget, amount_cents: 40_000)])
    expect(alice.token_accounts.find_by(budget: budget).balance_cents).to eq(60_000)
    expect(claude.token_accounts.find_by(budget: budget).balance_cents).to eq(40_000)
  end

  it "combines balances across deals when no single deal is enough" do
    budget_a = create_active_budget!(borrower: alice, investor: bob, amount_cents: 30_000)
    budget_b = create_active_budget!(borrower: alice, investor: bob, amount_cents: 25_000)

    parts = described_class.call(from_user: alice, to_user: claude, amount_cents: 50_000)

    expect(parts).to contain_exactly(
      described_class::TransferPart.new(budget: budget_b, amount_cents: 25_000),
      described_class::TransferPart.new(budget: budget_a, amount_cents: 25_000)
    )
    expect(alice.token_accounts.find_by(budget: budget_a).balance_cents).to eq(5_000)
    expect(alice.token_accounts.find_by(budget: budget_b).balance_cents).to eq(0)
    expect(claude.token_accounts.find_by(budget: budget_a).balance_cents).to eq(25_000)
    expect(claude.token_accounts.find_by(budget: budget_b).balance_cents).to eq(25_000)
  end

  it "prefers the requested deal when it has enough balance" do
    budget_a = create_active_budget!(borrower: alice, investor: bob, amount_cents: 100_000)
    budget_b = create_active_budget!(borrower: alice, investor: bob, amount_cents: 100_000)
    budget_a.token_accounts.find_by(user: alice).touch(time: 1.day.ago)

    parts = described_class.call(
      from_user: alice,
      to_user: claude,
      amount_cents: 25_000,
      preferred_budget: budget_b
    )

    expect(parts).to eq([described_class::TransferPart.new(budget: budget_b, amount_cents: 25_000)])
  end

  it "rejects transfers above the total spendable balance" do
    create_active_budget!(borrower: alice, investor: bob, amount_cents: 30_000)
    create_active_budget!(borrower: alice, investor: bob, amount_cents: 20_000)

    expect do
      described_class.call(from_user: alice, to_user: claude, amount_cents: 60_000)
    end.to raise_error(described_class::Error, I18n.t("services.tokens.transfer.insufficient_balance"))
  end
end
