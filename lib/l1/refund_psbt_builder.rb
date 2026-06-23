# frozen_string_literal: true

module L1
  # Path B refund PSBT — peg + investor 2-of-3, nLockTime a maturity + delay.
  class RefundPsbtBuilder
    def self.call(funding:, escrow:, peg_party:, investor:, bot:, budget:, signers:)
      new(funding:, escrow:, peg_party:, investor:, bot:, budget:, signers:).call
    end

    def initialize(funding:, escrow:, peg_party:, investor:, bot:, budget:, signers:)
      @funding = funding
      @escrow = escrow
      @peg_party = peg_party
      @investor = investor
      @bot = bot
      @budget = budget
      @signers = signers
    end

    def call
      locktime_height = budget.refund_locktime_height
      peg_sats = funding.peg_sats
      fee = Budget::ESTIMATED_SETTLEMENT_FEE_SATS
      investor_sats = funding.escrow_sats - peg_sats - fee
      raise Bitcoind::Error, "Invalid refund split" if investor_sats.negative?

      peg_address = refund_address(@peg_party)
      investor_address = refund_address(@investor)

      raw = global_client.call(
        "createrawtransaction",
        [{ txid: funding.txid, vout: funding.vout, sequence: 0xfffffffe }],
        [
          { peg_address => btc(peg_sats) },
          { investor_address => btc(investor_sats) }
        ],
        locktime_height
      )

      signed = sign_escrow_spend(raw)
      {
        locktime_height: locktime_height,
        hex: signed.fetch("hex"),
        complete: signed.fetch("complete"),
        peg_sats: peg_sats,
        investor_sats: investor_sats
      }
    end

    private

    attr_reader :funding, :escrow, :peg_party, :investor, :bot, :budget, :signers

    def global_client
      @global_client ||= Bitcoind::Client.new
    end

    def refund_address(party)
      return party.address if party.respond_to?(:address)

      descriptor = global_client.call("getdescriptorinfo", "wpkh(#{party.public_key_hex})").fetch("descriptor")
      global_client.call("deriveaddresses", descriptor).first
    end

    def sign_escrow_spend(raw)
      wifs = signers.map { |signer| signer_wif(signer) }
      prev = escrow_prevout

      global_client.call("signrawtransactionwithkey", raw, wifs, [prev])
    end

    def escrow_prevout
      tx = global_client.call("getrawtransaction", funding.txid, true)
      output = tx.fetch("vout")[funding.vout]

      {
        txid: funding.txid,
        vout: funding.vout,
        scriptPubKey: output.dig("scriptPubKey", "hex"),
        redeemScript: escrow.redeem_script_hex,
        witnessScript: escrow.witness_script_hex,
        amount: btc(funding.escrow_sats)
      }
    end

    def signer_wif(signer)
      return signer.wif if signer.respond_to?(:wif)
      return signer.wif_for_signing if signer.respond_to?(:wif_for_signing)

      raise Bitcoind::Error, "Signer without WIF for refund PSBT"
    end

    def btc(sats)
      format("%.8f", sats / 100_000_000.0)
    end
  end
end
