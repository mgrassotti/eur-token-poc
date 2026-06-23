# frozen_string_literal: true

module L1
  class RecordEscrowService
    def self.call(budget:, funding:, escrow:, peg_party:, investor:, bot:)
      new(budget:, funding:, escrow:, peg_party:, investor:, bot:).call
    end

    def initialize(budget:, funding:, escrow:, peg_party:, investor:, bot:)
      @budget = budget
      @funding = funding
      @escrow = escrow
      @peg_party = peg_party
      @investor = investor
      @bot = bot
    end

    def call
      refund_psbt = build_refund_psbt

      package = RecoveryPackage.build(
        budget: budget,
        funding: funding,
        escrow: escrow,
        peg_party: peg_party,
        investor: investor,
        bot: bot,
        refund_psbt: refund_psbt
      )

      budget.update!(
        peg_party_pubkey: pubkey_hex(peg_party),
        investor_pubkey: pubkey_hex(investor),
        bot_pubkey: pubkey_hex(bot),
        escrow_txid: funding.txid,
        escrow_vout: funding.vout,
        refund_delay_blocks: Budget::REFUND_DELAY_BLOCKS,
        recovery_package: package
      )

      budget.reload
    end

    private

    attr_reader :budget, :funding, :escrow, :peg_party, :investor, :bot

    def build_refund_psbt
      return unsigned_refund_metadata unless refund_signable?

      RefundPsbtBuilder.call(
        funding: funding,
        escrow: escrow,
        peg_party: peg_party,
        investor: investor,
        bot: bot,
        budget: budget,
        signers: [peg_party, investor]
      )
    end

    def refund_signable?
      signer_wif?(peg_party) && signer_wif?(investor)
    end

    def signer_wif?(party)
      party.respond_to?(:wif_for_signing) || party.respond_to?(:wif)
    end

    def unsigned_refund_metadata
      {
        locktime_height: budget.refund_locktime_height,
        hex: nil,
        complete: false,
        peg_sats: funding.peg_sats,
        investor_sats: nil
      }
    end

    def pubkey_hex(party)
      party.public_key_hex
    end
  end
end
