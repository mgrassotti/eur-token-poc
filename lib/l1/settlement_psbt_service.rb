# frozen_string_literal: true

module L1
  # Settlement maturity §5.1: PSBT asincrona — bot firma, poi co-firmatario 2-of-3, broadcast.
  class SettlementPsbtService
    class Error < StandardError; end

    SettlementPsbt = Data.define(
    :budget,
    :payoff,
    :holder_payouts,
    :raw_hex,
    :psbt,
    :hex,
    :complete,
    :signatures_applied,
      :co_signer
    ) do
      def signed_hex
        hex
      end
    end

    DEFAULT_CO_SIGNER = :investor

    def self.call(budget:, payoff:, holder_payouts:, co_signer: DEFAULT_CO_SIGNER)
      draft = build(budget:, payoff:, holder_payouts:, co_signer:)
      signed = sign!(draft, :bot)
      signed = sign!(signed, co_signer)
      broadcast!(signed)
    end

    def self.build(budget:, payoff:, holder_payouts:, co_signer: DEFAULT_CO_SIGNER)
      validate_co_signer!(co_signer)

      builder = SettlementTxBuilder.new(budget:, payoff:, holder_payouts:)
      raw_hex = builder.build_raw_hex
      psbt = builder.build_psbt(raw_hex)

      SettlementPsbt.new(
        budget: budget,
        payoff: payoff,
        holder_payouts: builder.holder_payouts,
        raw_hex: raw_hex,
        psbt: psbt,
        hex: nil,
        complete: false,
        signatures_applied: [],
        co_signer: co_signer
      )
    end

    def self.sign!(draft, role)
      role = role.to_sym
      raise Error, "PSBT già completa" if draft.complete

      wif = wif_for(draft.budget, role)
      hex = draft.hex.presence || draft.raw_hex
      builder = SettlementTxBuilder.new(
        budget: draft.budget,
        payoff: draft.payoff,
        holder_payouts: draft.holder_payouts.map { |p| { user: p.user, btc_sats: p.btc_sats } }
      )

      signed = Bitcoind::Client.new.call(
        "signrawtransactionwithkey",
        hex,
        [wif],
        [builder.escrow_prevout]
      )

      SettlementPsbt.new(
        budget: draft.budget,
        payoff: draft.payoff,
        holder_payouts: draft.holder_payouts,
        raw_hex: draft.raw_hex,
        psbt: draft.psbt,
        hex: signed.fetch("hex"),
        complete: signed.fetch("complete"),
        signatures_applied: draft.signatures_applied + [role],
        co_signer: draft.co_signer
      )
    end

    def self.broadcast!(draft)
      raise Error, "PSBT settlement incompleta (firme 2-of-3 mancanti)" unless draft.complete
      raise Error, "Hex firmata mancante" if draft.hex.blank?

      client = Bitcoind::Client.new
      txid = client.call("sendrawtransaction", draft.hex)
      confirm_regtest_block!

      txid
    end

    def self.validate_co_signer!(co_signer)
      role = co_signer.to_sym
      return if SignatureMatrix.valid_pair?(:bot, role)

      raise Error, "Co-firmatario #{role} non valido con bot (2-of-3)"
    end

    def self.wif_for(budget, role)
      case role.to_sym
      when :bot
        wif = budget.recovery_package.dig("bot_signing", "wif")
        raise Error, "Chiave bot mancante nel recovery package" if wif.blank?

        wif
      when :investor
        DealSigning.investor_wif_for(budget)
      when :peg_party
        DealSigning.peg_party_wif_for(budget)
      else
        raise Error, "Ruolo firmatario sconosciuto: #{role}"
      end
    end

    def self.confirm_regtest_block!
      RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET).mine_blocks(1)
    end

    private_class_method :validate_co_signer!, :wif_for, :confirm_regtest_block!
  end
end
