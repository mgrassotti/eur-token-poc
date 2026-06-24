# frozen_string_literal: true

require "rails_helper"

RSpec.describe L1::SettlementPsbtService, :l1_integration do
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }
  let(:peg) { 50_000 }
  let(:amount_eur_cents) { 100_000 }
  let(:budget) do
    borrower_sats = BtcConversion.eur_cents_to_sats(amount_eur_cents, peg)
    investor_sats = borrower_sats
    create(
      :budget,
      borrower: alice,
      investor: bob,
      status: :active,
      peg_eur_per_btc: peg,
      borrower_locked_sats: borrower_sats,
      investor_locked_sats: investor_sats,
      genesis_block_height: 0,
      maturity_block_height: 10_000
    ).tap do |record|
      CollateralLock.create!(
        budget: record,
        amount_sats: borrower_sats + investor_sats,
        locked_at: Time.current
      )
      TokenAccount.create!(user: alice, budget: record, balance_cents: amount_eur_cents)
    end
  end
  let(:payoff) do
    Payoffs::FloorEurCalculator.call(
      notional_eur_cents: budget.notional_eur_cents,
      notional_total_cents: budget.amount_eur_cents,
      holder_shares_cents: [amount_eur_cents],
      spot_eur_per_btc: peg,
      rate_bps_monthly: budget.rate_bps_monthly,
      months_elapsed: budget.months_elapsed,
      escrow_total_sats: budget.pool_sats
    )
  end
  let(:holder_payouts) { [{ user: alice, btc_sats: payoff.holder_allocations.first.btc_sats }] }

  before do
    allow(L1::UserWallet).to receive(:for) do |user|
      instance_double(L1::UserWallet, receive_address: "bcrt1settle#{user.id}")
    end

    budget.update!(
      peg_party_pubkey: "02#{"a" * 64}",
      investor_pubkey: "02#{"b" * 64}",
      bot_pubkey: "02#{"c" * 64}",
      escrow_txid: "abc123",
      escrow_vout: 0,
      recovery_package: {
        "escrow" => {
          "address" => "bcrt1escrow",
          "redeem_script_hex" => "5221#{"aa" * 33}21#{"bb" * 33}21#{"cc" * 33}53ae",
          "witness_script_hex" => "5221#{"aa" * 33}21#{"bb" * 33}21#{"cc" * 33}53ae",
          "amount_sats" => budget.pool_sats
        },
        "bot_signing" => { "wif" => "cTpBprivkeyWIFexample0000000000000000001" }
      }
    )
  end

  describe ".build" do
    it "raises when escrow is not provisioned" do
      budget.update!(escrow_txid: nil, peg_party_pubkey: nil)

      expect do
        described_class.build(budget: budget, payoff: payoff, holder_payouts: holder_payouts)
      end.to raise_error(described_class::Error, /Escrow L1 non provisionato/)
    end

    it "raises when bot signing key is missing" do
      package = budget.recovery_package.deep_dup
      package["bot_signing"] = {}
      budget.update!(recovery_package: package)

      expect do
        described_class.build(budget: budget, payoff: payoff, holder_payouts: holder_payouts)
      end.to raise_error(described_class::Error, /Chiave bot mancante/)
    end

    it "rejects invalid co-signer pairs" do
      expect do
        described_class.build(budget: budget, payoff: payoff, holder_payouts: holder_payouts, co_signer: :borrower)
      end.to raise_error(described_class::Error, /Co-firmatario/)
    end
  end

  describe ".broadcast!" do
    it "requires a complete draft" do
      draft = described_class::SettlementPsbt.new(
        budget: budget,
        payoff: payoff,
        holder_payouts: [],
        raw_hex: "00",
        psbt: "cHNidP8B",
        hex: "00",
        complete: false,
        signatures_applied: [:bot],
        co_signer: :investor
      )

      expect do
        described_class.broadcast!(draft)
      end.to raise_error(described_class::Error, /incompleta/)
    end
  end
end
