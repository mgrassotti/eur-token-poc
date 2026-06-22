# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::CreateService do
  let(:alice) { create(:user) }

  before do
    alice.btc_account.update!(balance_sats: 10_000_000)
    MarketRate.current.update!(btc_eur_per_btc: 60_000)
  end

  it "locks borrower collateral and creates pending budget" do
    budget = described_class.call(
      borrower: alice,
      amount_eur_cents: 100_000,
      period_start: Date.current,
      period_end: Date.current + 1.month
    )

    locked_sats = BtcConversion.eur_cents_to_sats(100_000, 60_000)
    expect(budget.borrower_locked_sats).to eq(locked_sats)
    expect(budget.collateral_eur_cents).to eq(100_000)
    expect(budget.peg_eur_per_btc).to eq(60_000)
    expect(alice.btc_account.reload.balance_sats).to eq(10_000_000 - locked_sats)
    expect(budget).to be_pending
  end

  it "rejects insufficient savings balance" do
    alice.btc_account.update!(balance_sats: 1000)

    expect do
      described_class.call(
        borrower: alice,
        amount_eur_cents: 100_000,
        period_start: Date.current,
        period_end: Date.current + 1.month
      )
    end.to raise_error(Budgets::CreateService::Error, "Saldo insufficiente sul conto di riserva")
  end
end
