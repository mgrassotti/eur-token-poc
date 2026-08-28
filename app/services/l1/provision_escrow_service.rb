# frozen_string_literal: true

module L1
  class ProvisionEscrowService
    class Error < StandardError; end

    def self.call(budget:, auto_sign_wallets: nil)
      new(budget: budget, auto_sign_wallets: auto_sign_wallets).call
    end

    def initialize(budget:, auto_sign_wallets: nil)
      @budget = budget
      @auto_sign_wallets = auto_sign_wallets
    end

    def call
      return budget if budget.l1_multisig_provisioned?

      validate_bitcoind!

      ensure_chain_ready!

      # Fase 1: fund the DLC from client-supplied peg + investor UTXOs.
      # auto_sign_wallets (regtest) signs immediately; otherwise PSBT sign round.
      setup_dlc!(budget.reload)

      if budget.l1_multisig_provisioned?
        Rgb::IssueService.call(budget: budget.reload)
      end

      budget.reload
    rescue Bitcoind::Error => e
      raise Error, I18n.t("services.l1.provision_escrow.not_provisioned", message: e.message)
    end

    private

    attr_reader :budget

    def setup_dlc!(budget)
      Dlc::ContractSetupService.call(budget: budget, auto_sign_wallets: @auto_sign_wallets)
    end

    def ensure_chain_ready!
      RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET).ensure_chain_ready!
    end

    def validate_bitcoind!
      return if Bitcoind::Client.new.available?

      raise Error, I18n.t("services.shared.bitcoind_unreachable")
    end
  end
end
