# frozen_string_literal: true

module L1
  # Persiste nel recovery package la PSBT maturity (unsigned) e i metadati payoff.
  class SettlementPsbtTemplateService
    def self.call(budget:, payoff:, holder_payouts:, draft: nil, end_btc_eur_rate: nil)
      new(budget:, payoff:, holder_payouts:, draft:, end_btc_eur_rate:).call
    end

    def initialize(budget:, payoff:, holder_payouts:, draft: nil, end_btc_eur_rate: nil)
      @budget = budget
      @payoff = payoff
      @holder_payouts = holder_payouts
      @draft = draft
      @end_btc_eur_rate = end_btc_eur_rate
    end

    def call
      return budget unless budget.l1_multisig_provisioned?

      package = budget.recovery_package.deep_dup
      built = draft || build_draft

      package["psbt_maturity"] = maturity_section(built)
      package["psbt_maturity_template"] = package["psbt_maturity"]

      budget.update!(recovery_package: package)
      budget.reload
    end

    private

    attr_reader :budget, :payoff, :holder_payouts, :draft, :end_btc_eur_rate

    def build_draft
      SettlementPsbtService.build(budget: budget, payoff: payoff, holder_payouts: holder_payouts)
    rescue SettlementPsbtService::Error
      nil
    end

    def maturity_section(built)
      return legacy_template unless built

      builder = SettlementTxBuilder.new(budget: budget, payoff: payoff, holder_payouts: holder_payouts)

      {
        mode: "async PSBT maturity",
        psbt: built.psbt,
        raw_hex: built.raw_hex,
        co_signers: [:bot, built.co_signer],
        total_holder_sats: payoff.total_holder_sats,
        investor_remainder_sats: payoff.investor_remainder_sats,
        escrow_outpoint: budget.escrow_outpoint,
        insolvent: payoff.insolvent,
        end_btc_eur_rate: end_btc_eur_rate,
        outputs: builder.output_metadata,
        note: "Firmare con bot + co_signer (2-of-3), poi broadcast"
      }
    end

    def legacy_template
      {
        total_holder_sats: payoff.total_holder_sats,
        investor_remainder_sats: payoff.investor_remainder_sats,
        escrow_outpoint: budget.escrow_outpoint,
        insolvent: payoff.insolvent,
        note: "Cooperative 2-of-3 spend at maturity (bot + peg_party or bot + investor)"
      }
    end
  end
end
