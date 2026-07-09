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

      validate_bitcoind!

      ensure_chain_ready!

      # Fase 1: no separate 2-of-2 escrow. Fund the DLC straight from the peg +
      # investor L1 reserves first — that single 2-of-2 funding tx IS the
      # collateral lock and records the provisioning flags (peg/investor pubkeys +
      # escrow outpoint) that RGB issuance gates on. Then issue RGB.
      setup_dlc!(budget.reload)

      Rgb::IssueService.call(budget: budget.reload)

      sync_wallet_balances!

      budget.reload
    rescue Bitcoind::Error => e
      raise Error, I18n.t("services.l1.provision_escrow.not_provisioned", message: e.message)
    end

    private

    attr_reader :budget

    # Fund the 2-of-2 numeric DLC from the users' reserves (oracle announcement +
    # funding tx). This also records the collateral lock (funding outpoint +
    # party pubkeys) on the budget. Setup failures abort activation so the
    # misconfiguration is visible rather than silently leaving the deal unsettled.
    def setup_dlc!(budget)
      Dlc::ContractSetupService.call(budget: budget)
    end

    def ensure_chain_ready!
      RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET).ensure_chain_ready!
    end

    def sync_wallet_balances!
      SyncReserveBalanceService.call(user: budget.borrower)
      SyncReserveBalanceService.call(user: budget.investor)
    end

    def validate_bitcoind!
      return if Bitcoind::Client.new.available?

      raise Error, I18n.t("services.shared.bitcoind_unreachable")
    end
  end
end
