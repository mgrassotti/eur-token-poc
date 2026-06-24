# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tokens::TransferService do
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }
  let(:claude) { create(:user) }

  let!(:budget) do
    alice.btc_account.update!(balance_sats: 10_000_000)
    MarketRate.current.update!(btc_eur_per_btc: 60_000)
    Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: 100_000,
      period_start: Date.current,
      period_end: Date.current + 1.month
    )
  end

  before do
    bob.btc_account.update!(balance_sats: 5_000_000)
    Budgets::ActivateService.call(budget: budget, investor: bob)
  end

  it "transfers tokens between users" do
    claude.btc_account.update!(escrow_identity_pubkey: "02#{"c" * 64}")

    described_class.call(budget: budget, from_user: alice, to_user: claude, amount_cents: 25_000)

    expect(alice.token_accounts.find_by(budget: budget).balance_cents).to eq(75_000)
    expect(claude.token_accounts.find_by(budget: budget).balance_cents).to eq(25_000)
  end

  it "rejects insufficient balance" do
    expect do
      described_class.call(budget: budget, from_user: alice, to_user: claude, amount_cents: 200_000)
    end.to raise_error(Tokens::TransferService::Error, "Insufficient token balance")
  end
end
