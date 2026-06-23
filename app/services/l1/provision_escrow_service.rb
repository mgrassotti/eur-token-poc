# frozen_string_literal: true

module L1
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

      ensure_chain_ready!

      funding = FundingPsbtService.call(budget: budget)

      sync_wallet_balances!

      RecordEscrowService.call(
        budget: budget,
        funding: funding,
        escrow: funding.escrow,
        peg_party: funding.peg_party,
        investor: funding.investor,
        bot: funding.bot
      )
    rescue Bitcoind::Error => e
      raise Error, "Escrow L1 non provisionato: #{e.message}"
    end

    private

    attr_reader :budget

    def ensure_chain_ready!
      RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET).ensure_chain_ready!
    end

    def sync_wallet_balances!
      SyncReserveBalanceService.call(user: budget.borrower)
      SyncReserveBalanceService.call(user: budget.investor)
    end

    def validate_bitcoind!
      return if Bitcoind::Client.new.available?

      raise Error, "L1 abilitato ma bitcoind regtest non raggiungibile. Avvia: ./bin/regtest up"
    end
  end
end
