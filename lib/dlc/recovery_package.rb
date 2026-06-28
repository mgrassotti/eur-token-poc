# frozen_string_literal: true

module Dlc
  # Self-custody recovery bundle for the DLC path: everything a party needs to
  # claim funds without the facilitator — the oracle announcement/attestation,
  # the ddk contract + funding outpoint, the executed CET, and the timelocked
  # refund coordinates. Mirrors L1::RecoveryPackage for the legacy escrow.
  class RecoveryPackage
    VERSION = 1

    def self.build(budget:)
      new(budget:).to_h
    end

    def initialize(budget:)
      @budget = budget
      @contract = budget.dlc_contract
      @settlement = budget.dlc_settlement
    end

    def to_h
      raise ArgumentError, "Budget #{@budget.id} senza contratto DLC" if @contract.nil?

      {
        version: VERSION,
        deal_id: @budget.id,
        oracle: oracle_section,
        contract: contract_section,
        cet: cet_section,
        refund: refund_section
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    private

    def oracle_section
      {
        event_id: @contract.oracle_event_id,
        announcement: @contract.oracle_announcement,
        unit: @contract.unit,
        num_digits: @contract.num_digits,
        maturity_epoch: @contract.maturity_epoch,
        attestation: @settlement&.attestation,
        outcome: @settlement&.outcome
      }
    end

    def contract_section
      {
        ddk_contract_id: @contract.ddk_contract_id,
        funding_outpoint: @contract.funding_outpoint,
        peg_collateral_sats: @contract.peg_collateral_sats,
        investor_collateral_sats: @contract.investor_collateral_sats,
        status: @contract.status
      }
    end

    def cet_section
      return { note: "Non ancora eseguito (attendere maturity)" } if @settlement.nil?

      {
        txid: @settlement.cet_txid,
        outcome: @settlement.outcome,
        peg_pot_sats: @settlement.peg_pot_sats,
        investor_sats: @settlement.investor_sats,
        distribution: @budget.recovery_package&.dig("dlc_distribution")
      }
    end

    def refund_section
      {
        locktime_height: @budget.refund_locktime_height,
        note: "Path B — refund 2-of-2 {peg, investor} dopo refund_delay_blocks"
      }
    end
  end
end
