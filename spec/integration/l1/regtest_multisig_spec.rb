# frozen_string_literal: true

require "rails_helper"

RSpec.describe "L1 regtest multisig", :regtest do
  def bitcoind_available?
    L1::Bitcoind::Client.new.available?
  end

  before do
    skip "Start regtest: docker compose -f docker-compose.regtest.yml up -d" unless bitcoind_available?
  end

  it "funds a 2-of-3 P2WSH escrow (Alice 1M + Bob 1M)" do
    L1::RegtestHarness.with_available_bitcoind do |harness|
      funding = harness.fund_escrow!(peg_sats: 1_000_000, investor_sats: 1_000_000)

      expect(funding.escrow_sats).to eq(2_000_000)
      expect(funding.txid).to be_present
      expect(harness.escrow.address).to start_with("bcrt1")
    end
  end

  it "settles with peg_party + investor without bot (FloorEUR-style split)" do
    L1::RegtestHarness.with_available_bitcoind do |harness|
      funding = harness.fund_escrow!(peg_sats: 1_000_000, investor_sats: 1_000_000)
      escrow_sats = funding.escrow_sats
      fee = Budget::ESTIMATED_SETTLEMENT_FEE_SATS
      distributable = escrow_sats - fee
      holder_sats = 1_060_000
      holder_sats = distributable if holder_sats > distributable
      investor_sats = distributable - holder_sats

      result = harness.spend_escrow!(
        funding: funding,
        holder_sats: holder_sats,
        investor_sats: investor_sats,
        signers: [harness.peg_party, harness.investor]
      )

      expect(result.txid).to be_present
      expect(L1::SignatureMatrix.valid_pair?(:peg_party, :investor)).to be(true)
    end
  end

  it "rejects bot-only spend (1-of-3 insufficient)" do
    L1::RegtestHarness.with_available_bitcoind do |harness|
      funding = harness.fund_escrow!(peg_sats: 500_000, investor_sats: 500_000)

      signed = harness.incomplete_escrow_sign(funding: funding, signers: [harness.bot])

      expect(signed.fetch("complete")).to be(false)
      expect(L1::SignatureMatrix.bot_only?([harness.bot])).to be(true)
    end
  end

  it "builds a timelock refund tx template (Path B)" do
    L1::RegtestHarness.with_available_bitcoind do |harness|
      funding = harness.fund_escrow!(peg_sats: 600_000, investor_sats: 400_000)
      locktime = harness.current_height + 10

      signed = harness.build_refund_tx(
        funding: funding,
        peg_sats: 600_000,
        investor_sats: funding.escrow_sats - 600_000 - Budget::ESTIMATED_SETTLEMENT_FEE_SATS,
        locktime_height: locktime
      )

      expect(signed.fetch("complete")).to be(true)

      decoded = harness.global_client.call("decoderawtransaction", signed.fetch("hex"))
      expect(decoded.fetch("locktime")).to eq(locktime)
    end
  end

  it "records recovery package on Budget" do
    alice = create(:user, name: "Alice")
    bob = create(:user, name: "Bob")

    L1::RegtestHarness.with_available_bitcoind do |harness|
      funding = harness.fund_escrow!(peg_sats: 1_000_000, investor_sats: 1_000_000)
      budget = setup_active_budget!(
        borrower: alice,
        investor: bob,
        amount_eur_cents: 100_000,
        peg: 50_000,
        block_height: 800_000
      )

      updated = L1::RecordEscrowService.call(
        budget: budget,
        funding: funding,
        escrow: harness.escrow,
        peg_party: harness.peg_party,
        investor: harness.investor,
        bot: harness.bot
      )

      expect(updated.l1_multisig_provisioned?).to be(true)
      expect(updated.recovery_package["deal_params"]["deal_id"]).to eq(budget.id)
      expect(updated.recovery_package["escrow"]["outpoint"]).to eq("#{funding.txid}:0")
    end
  end
end
