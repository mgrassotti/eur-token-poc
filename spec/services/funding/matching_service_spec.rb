# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::MatchingService do
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }

  def queued_request(user, role:, amount: 100_000, address: "bcrt1q#{role}#{user.id.to_s.rjust(20, "0")}")
    FundingRequest.create!(
      user: user,
      role: role,
      status: :queued,
      amount_eur_cents: amount,
      remaining_eur_cents: amount,
      payout_mode: :keep_btc,
      receive_address: address,
      change_address: "#{address}c",
      identity_pubkey: "02#{"a" * 64}",
      funding_inputs: [ { "txid" => "aa" * 32, "vout" => 0, "amount_sats" => 3_000_000 } ]
    )
  end

  before do
    MarketRate.current.update!(btc_eur_per_btc: 50_000)
    alice.btc_account.update!(reserve_receive_address: "bcrt1qsaver#{alice.id.to_s.rjust(20, "0")}", balance_sats: 10_000_000)
    bob.btc_account.update!(reserve_receive_address: "bcrt1qinvest#{bob.id.to_s.rjust(19, "0")}", balance_sats: 10_000_000)
    allow_any_instance_of(L1::Bitcoind::Client).to receive(:available?).and_return(true)
    allow(L1::UtxoSetValidator).to receive(:call)
  end

  it "opens a DLC budget between the first saver and investor with capacity" do
    saver = queued_request(alice, role: :saver, address: alice.btc_account.reserve_receive_address)
    investor = queued_request(bob, role: :investor, address: bob.btc_account.reserve_receive_address, amount: 200_000)

    result = described_class.call

    expect(result.budgets.size).to eq(1)
    budget = result.budgets.first
    expect(budget.borrower).to eq(alice)
    expect(budget.investor).to eq(bob)
    expect(budget.amount_eur_cents).to eq(100_000)
    expect(budget.rate_bps_monthly).to eq(100)
    expect(budget).to be_active
    expect(saver.reload).to be_matched
    expect(investor.reload).to be_awaiting_deposit
    expect(investor.remaining_eur_cents).to eq(100_000)
  end

  it "does not match a saver with herself" do
    queued_request(alice, role: :saver, address: alice.btc_account.reserve_receive_address)
    queued_request(alice, role: :investor, address: "#{alice.btc_account.reserve_receive_address}i")

    expect(described_class.call.budgets).to be_empty
  end

  it "sizes leftover investor deposits against remaining capacity, not the original amount" do
    queued_request(alice, role: :saver, address: alice.btc_account.reserve_receive_address)
    investor = queued_request(bob, role: :investor, address: bob.btc_account.reserve_receive_address, amount: 200_000)

    described_class.call
    investor.reload

    expect(investor.remaining_eur_cents).to eq(100_000)
    expect(investor.required_sats).to eq(
      BtcConversion.eur_cents_to_sats(100_000, 50_000) + Dlc::ContractSetupService::FUNDING_FEE_BUFFER_SATS
    )
  end
end
