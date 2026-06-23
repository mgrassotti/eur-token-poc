# frozen_string_literal: true

module L1
  # Persists on-chain escrow metadata on a Budget after regtest funding.
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
      package = RecoveryPackage.build(
        budget: budget,
        funding: funding,
        escrow: escrow,
        peg_party: peg_party,
        investor: investor,
        bot: bot
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

    def pubkey_hex(party)
      party.public_key_hex
    end
  end
end
