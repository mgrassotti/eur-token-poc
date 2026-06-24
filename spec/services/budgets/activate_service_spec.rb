# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::ActivateService do
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }

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
  end

  it "locks collateral, mints tokens and activates budget at current rate" do
    peg = 60_000
    bob_collateral_sats = budget.collateral_sats_at_peg(peg)
    starting_bob_sats = bob.balance_sats
    alice_sats_after_create = alice.btc_account.balance_sats

    described_class.call(budget: budget, investor: bob)

    expect(budget.reload).to be_active
    expect(budget.peg_eur_per_btc).to eq(peg)
    expect(budget.collateral_lock.amount_sats).to eq(bob_collateral_sats + budget.borrower_locked_sats)
    expect(budget.investor_locked_sats).to eq(bob_collateral_sats)
    expect(alice.btc_account.reload.balance_sats).to eq(alice_sats_after_create)
    expect(bob.btc_account.reload.balance_sats).to eq(starting_bob_sats)
    expect(alice.token_accounts.find_by(budget: budget).balance_cents).to eq(100_000)
    expect(budget.genesis_block_height).to eq(ChainState.block_height)
    expect(budget.maturity_block_height).to eq(budget.genesis_block_height + budget.symbolic_months_duration * Budget::BLOCKS_PER_MONTH)
  end

  it "fixes peg and investor collateral at the current rate on activation" do
    MarketRate.current.update!(btc_eur_per_btc: 70_000)

    described_class.call(budget: budget, investor: bob)

    expect(budget.reload.peg_eur_per_btc).to eq(70_000)
    expect(budget.investor_locked_sats).to eq(budget.collateral_sats_at_peg(70_000))
  end

  it "rejects activation without current market rate" do
    MarketRate.current.update!(btc_eur_per_btc: nil)

    expect do
      described_class.call(budget: budget, investor: bob)
    end.to raise_error(Budgets::ActivateService::Error, "L'admin deve impostare il cambio BTC/€ corrente")
  end

  it "rejects insufficient collateral" do
    bob.btc_account.update!(balance_sats: 1000)

    expect do
      described_class.call(budget: budget, investor: bob)
    end.to raise_error(Budgets::ActivateService::Error, /Saldo insufficiente sul conto di riserva/)
  end

  it "rejects activation when bitcoind is down" do
    unavailable = instance_double(L1::Bitcoind::Client, available?: false)
    allow(L1::Bitcoind::Client).to receive(:new).and_return(unavailable)

    expect do
      described_class.call(budget: budget, investor: bob)
    end.to raise_error(Budgets::ActivateService::Error, /bitcoind regtest/)
  end
end
