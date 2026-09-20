# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::SimulateSepaOut do
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }

  it "debits the MAT bank and records an outbound SEPA after a EUR payout" do
    bank = BankAccount.default
    bank.update!(balance_eur_cents: 200_000)

    budget = setup_active_budget!(borrower: alice, investor: bob, amount_eur_cents: 100_000, peg: 50_000)
    budget.update!(saver_payout_mode: :eur, saver_payout_iban: "IT60X1111111111111111111111")
    advance_to_maturity!(budget)
    Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: 50_000)

    liability = budget.liability_eur_cents(at_height: budget.maturity_block_height)
    transfer = BankTransfer.outbound.last
    expect(transfer).to be_present
    expect(transfer.amount_eur_cents).to eq(liability)
    expect(transfer.counterparty_iban).to eq("IT60X1111111111111111111111")
    expect(bank.reload.balance_eur_cents).to eq(200_000 - liability)
  end
end
