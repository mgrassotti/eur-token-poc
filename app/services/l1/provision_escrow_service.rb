# frozen_string_literal: true

module L1
  # Funds regtest 2-of-3 escrow after budget activation and stores recovery package.
  class ProvisionEscrowService
    class Error < StandardError; end

    def self.call(budget:)
      new(budget:).call
    end

    def initialize(budget:)
      @budget = budget
    end

    def call
      return budget if budget.l1_multisig_provisioned?
      return budget unless L1.enabled?

      validate_bitcoind!

      harness = RegtestHarness.new(wallet_name: wallet_name)
      harness.ensure_chain_ready!

      funding = harness.fund_escrow!(
        peg_sats: budget.borrower_locked_sats,
        investor_sats: budget.investor_locked_sats
      )

      RecordEscrowService.call(
        budget: budget,
        funding: funding,
        escrow: harness.escrow,
        peg_party: harness.peg_party,
        investor: harness.investor,
        bot: harness.bot
      )
    rescue Bitcoind::Error => e
      raise Error, "Escrow L1 non provisionato: #{e.message}"
    end

    private

    attr_reader :budget

    def wallet_name
      L1::SHARED_REGTEST_WALLET
    end

    def validate_bitcoind!
      return if Bitcoind::Client.new.available?

      raise Error, "L1 abilitato ma bitcoind regtest non raggiungibile. Avvia: ./bin/regtest up"
    end
  end
end
