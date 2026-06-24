# frozen_string_literal: true

module L1
  # Costruisce la transazione di settlement maturity (output holder + investor).
  class SettlementTxBuilder
    HolderPayout = Data.define(:user, :btc_sats, :address)

    def self.holder_payouts_from(holder_payouts)
      holder_payouts.map do |payout|
        user = payout.fetch(:user)
        sats = payout.fetch(:btc_sats)
        wallet = UserWallet.for(user)
        address = wallet.receive_address(label: "settlement_holder")
        HolderPayout.new(user: user, btc_sats: sats, address: address)
      end
    end

    def initialize(budget:, payoff:, holder_payouts:)
      @budget = budget
      @payoff = payoff
      @holder_payouts = self.class.holder_payouts_from(holder_payouts)
      @global_client = Bitcoind::Client.new
    end

    def build_raw_hex
      validate!

      outputs = holder_outputs
      if payoff.investor_remainder_sats.positive?
        investor_wallet = UserWallet.for(budget.investor)
        address = investor_wallet.receive_address(label: "settlement_investor")
        outputs << { address => btc(payoff.investor_remainder_sats) }
      end

      raise SettlementPsbtService::Error, "Nessun output settlement" if outputs.empty?

      @global_client.call(
        "createrawtransaction",
        [{ txid: budget.escrow_txid, vout: budget.escrow_vout }],
        outputs
      )
    end

    def build_psbt(raw_hex = build_raw_hex)
      @global_client.call("converttopsbt", raw_hex, true)
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

    def output_metadata
      rows = holder_payouts.map do |payout|
        {
          role: "holder",
          user_id: payout.user.id,
          address: payout.address,
          btc_sats: payout.btc_sats
        }
      end

      if payoff.investor_remainder_sats.positive?
        investor_wallet = UserWallet.for(budget.investor)
        rows << {
          role: "investor",
          user_id: budget.investor_id,
          address: investor_wallet.receive_address(label: "settlement_investor"),
          btc_sats: payoff.investor_remainder_sats
        }
      end

      rows
    end

    attr_reader :holder_payouts

    private

    attr_reader :budget, :payoff

    def validate!
      raise SettlementPsbtService::Error, "Escrow L1 non provisionato" unless budget.l1_multisig_provisioned?
      raise SettlementPsbtService::Error, "Recovery package mancante" unless budget.recovery_package.present?

      bot_wif = budget.recovery_package.dig("bot_signing", "wif")
      raise SettlementPsbtService::Error, "Chiave bot mancante nel recovery package" if bot_wif.blank?

      raise SettlementPsbtService::Error, "Output settlement non coerenti con il payoff" unless output_total_sats == payoff.distributable_sats
    end

    def holder_outputs
      holder_payouts.filter_map do |payout|
        next unless payout.btc_sats.positive?

        { payout.address => btc(payout.btc_sats) }
      end
    end

    def output_total_sats
      holder_payouts.sum(&:btc_sats) + payoff.investor_remainder_sats
    end

    def recovery_escrow
      package = budget.recovery_package
      Escrow::Result.new(
        address: package.dig("escrow", "address"),
        redeem_script_hex: package.dig("escrow", "redeem_script_hex"),
        witness_script_hex: package.dig("escrow", "witness_script_hex"),
        pubkeys_hex: [budget.peg_party_pubkey, budget.investor_pubkey, budget.bot_pubkey].compact.sort
      )
    end

    def escrow_amount_sats
      amount = budget.recovery_package.dig("escrow", "amount_sats").to_i
      amount.positive? ? amount : budget.pool_sats
    end

    def btc(sats)
      format("%.8f", sats / 100_000_000.0)
    end
  end
end
