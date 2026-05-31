# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::ActivateService do
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }
  let(:budget) { create(:budget, borrower: alice, amount_eur_cents: 100_000, collateral_eur_cents: 200_000) }

  before { bob.btc_account.update!(balance_sats: 5_000_000) }

  it "locks collateral, mints tokens and activates budget" do
    peg = 60_000
    collateral_sats = budget.collateral_sats_at_peg(peg)
    starting_bob_sats = bob.balance_sats

    described_class.call(budget: budget, investor: bob, peg_eur_per_btc: peg)

    expect(budget.reload).to be_active
    expect(budget.peg_eur_per_btc).to eq(peg)
    expect(budget.collateral_lock.amount_sats).to eq(collateral_sats)
    expect(bob.btc_account.reload.balance_sats).to eq(starting_bob_sats - collateral_sats)
    expect(alice.token_accounts.find_by(budget: budget).balance_cents).to eq(100_000)
  end

  it "rejects insufficient collateral" do
    bob.btc_account.update!(balance_sats: 1000)

    expect do
      described_class.call(budget: budget, investor: bob, peg_eur_per_btc: 60_000)
    end.to raise_error(Budgets::ActivateService::Error, "Insufficient BTC balance for collateral")
  end
end
