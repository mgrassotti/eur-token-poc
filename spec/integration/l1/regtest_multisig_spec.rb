# frozen_string_literal: true

require "rails_helper"

RSpec.describe "L1 regtest multisig", :regtest do
  def bitcoind_available?
    L1::Bitcoind::Client.new.available?
  end

  before do
    skip "Start regtest: docker compose -f docker-compose.regtest.yml up -d" unless bitcoind_available?
  end

  it "funds a 2-of-2 P2WSH escrow (Alice 1M + Bob 1M)" do
    L1::RegtestHarness.with_available_bitcoind do |harness|
      funding = harness.fund_escrow!(peg_sats: 1_000_000, investor_sats: 1_000_000)

      expect(funding.escrow_sats).to eq(2_000_000)
      expect(funding.txid).to be_present
      expect(harness.escrow.address).to start_with("bcrt1")
    end
  end

  it "broadcasts timelock refund after locktime (Path B end-to-end)" do
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

      harness.mine_blocks(11)
      txid = harness.broadcast_refund!(signed_hex: signed.fetch("hex"), locktime_height: locktime)

      expect(txid).to be_present
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

end
