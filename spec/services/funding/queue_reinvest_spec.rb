# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::QueueReinvest do
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }

  it "queues a new saver request for FloorEUR liability after settlement" do
    alice.btc_account.update!(reserve_receive_address: "bcrt1qalicesaver000000000000000000001")
    budget = setup_active_budget!(borrower: alice, investor: bob, amount_eur_cents: 100_000, peg: 50_000)
    budget.update!(
      saver_payout_mode: :reinvest,
      investor_payout_mode: :keep_btc,
      funding_address: alice.btc_account.reserve_receive_address
    )
    advance_to_maturity!(budget)
    Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: 50_000)

    request = FundingRequest.saver.where(user: alice).order(:id).last
    expect(request).to be_present
    expect(request).to be_awaiting_deposit
    expect(request.payout_mode).to eq("reinvest")
    expect(request.amount_eur_cents).to eq(budget.liability_eur_cents(at_height: budget.maturity_block_height))
  end

  it "queues leftover investor capacity after settlement when they chose reinvest" do
    budget = setup_active_budget!(borrower: alice, investor: bob, amount_eur_cents: 100_000, peg: 50_000)
    budget.update!(
      saver_payout_mode: :keep_btc,
      investor_payout_mode: :reinvest,
      investor_payout_address: bob.btc_account.reserve_receive_address
    )
    advance_to_maturity!(budget)
    result = Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: 50_000)

    request = FundingRequest.investor.where(user: bob).order(:id).last
    expect(request).to be_present
    expect(request).to be_awaiting_deposit
    expect(request.amount_eur_cents).to eq(
      BtcConversion.sats_to_eur_cents(result.investor_btc_sats, 50_000)
    )
  end
end
