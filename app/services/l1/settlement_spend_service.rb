# frozen_string_literal: true

module L1
  # Spend cooperativo 2-of-3 dall'escrow a maturity (bot + investor) — MULTISIG-SPEC §5.
  class SettlementSpendService
    class Error < StandardError; end

    HolderPayout = Data.define(:user, :btc_sats)

    def self.call(budget:, payoff:, holder_payouts:)
      new(budget:, payoff:, holder_payouts:).call
    end

    def initialize(budget:, payoff:, holder_payouts:)
      @budget = budget
      @payoff = payoff
      @holder_payouts = holder_payouts.map { |p| HolderPayout.new(user: p.fetch(:user), btc_sats: p.fetch(:btc_sats)) }
      @global_client = Bitcoind::Client.new
    end

    def call
      validate!

      raw = build_raw_transaction
      signed = sign_escrow_spend(raw)
      unless signed.fetch("complete")
        detail = signed.fetch("errors", []).map { |e| e["error"] }.compact.join("; ")
        raise Error, "Settlement tx incompleta (firme 2-of-3 mancanti)#{detail.present? ? ": #{detail}" : ""}"
      end

      txid = @global_client.call("sendrawtransaction", signed.fetch("hex"))
      confirm_regtest_block!

      txid
    end

    private

    attr_reader :budget, :payoff, :holder_payouts

    def validate!
      raise Error, "Escrow L1 non provisionato" unless budget.l1_multisig_provisioned?
      raise Error, "Recovery package mancante" unless budget.recovery_package.present?

      bot_wif = budget.recovery_package.dig("bot_signing", "wif")
      raise Error, "Chiave bot mancante nel recovery package" if bot_wif.blank?

      raise Error, "Output settlement non coerenti con il payoff" unless output_total_sats == payoff.distributable_sats
    end

    def build_raw_transaction
      outputs = []

      holder_payouts.each do |payout|
        next unless payout.btc_sats.positive?

        wallet = UserWallet.for(payout.user)
        address = wallet.receive_address(label: "settlement_holder")
        outputs << { address => btc(payout.btc_sats) }
      end

      if payoff.investor_remainder_sats.positive?
        investor_wallet = UserWallet.for(budget.investor)
        address = investor_wallet.receive_address(label: "settlement_investor")
        outputs << { address => btc(payoff.investor_remainder_sats) }
      end

      raise Error, "Nessun output settlement" if outputs.empty?

      @global_client.call(
        "createrawtransaction",
        [{ txid: budget.escrow_txid, vout: budget.escrow_vout }],
        outputs
      )
    end

    def sign_escrow_spend(raw)
      wifs = [
        budget.recovery_package.dig("bot_signing", "wif"),
        DealSigning.investor_wif_for(budget)
      ]
      @global_client.call("signrawtransactionwithkey", raw, wifs, [escrow_prevout])
    end

    def escrow_prevout
      tx = @global_client.call("getrawtransaction", budget.escrow_txid, true)
      output = tx.fetch("vout")[budget.escrow_vout]
      escrow = recovery_escrow

      {
        txid: budget.escrow_txid,
        vout: budget.escrow_vout,
        scriptPubKey: output.dig("scriptPubKey", "hex"),
        redeemScript: escrow.redeem_script_hex,
        witnessScript: escrow.witness_script_hex,
        amount: btc(escrow_amount_sats)
      }
    end

    def recovery_escrow
      package = budget.recovery_package
      Escrow::Result.new(
        address: package.dig("escrow", "address"),
        redeem_script_hex: package.dig("escrow", "redeem_script_hex"),
        witness_script_hex: package.dig("escrow", "redeem_script_hex"),
        pubkeys_hex: [budget.peg_party_pubkey, budget.investor_pubkey, budget.bot_pubkey].compact.sort
      )
    end

    def escrow_amount_sats
      budget.recovery_package.dig("escrow", "amount_sats").to_i.positive? ? budget.recovery_package.dig("escrow", "amount_sats").to_i : budget.pool_sats
    end

    def output_total_sats
      holder_payouts.sum(&:btc_sats) + payoff.investor_remainder_sats
    end

    def confirm_regtest_block!
      RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET).mine_blocks(1)
    end

    def btc(sats)
      format("%.8f", sats / 100_000_000.0)
    end
  end
end
