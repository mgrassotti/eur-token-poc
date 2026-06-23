# frozen_string_literal: true

module L1
  # Aggiorna il recovery package con il template settlement post-ExecuteService.
  class SettlementPsbtTemplateService
    def self.call(budget:, payoff:)
      new(budget:, payoff:).call
    end

    def initialize(budget:, payoff:)
      @budget = budget
      @payoff = payoff
    end

    def call
      return budget unless budget.l1_multisig_provisioned?

      package = budget.recovery_package.deep_dup
      package["psbt_maturity_template"] = {
        total_holder_sats: payoff.total_holder_sats,
        investor_remainder_sats: payoff.investor_remainder_sats,
        escrow_outpoint: budget.escrow_outpoint,
        insolvent: payoff.insolvent,
        note: "Cooperative 2-of-3 spend at maturity (bot + peg_party or bot + investor)"
      }

      budget.update!(recovery_package: package)
      budget.reload
    end

    private

    attr_reader :budget, :payoff
  end
end
