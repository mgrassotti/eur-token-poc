# frozen_string_literal: true

module Dlc
  # Maturity hook: fetch the oracle attestation for the observed price and
  # execute the matching CET on the ddk node, splitting funding into peg_pot
  # (holders) and investor remainder. Persists a DlcSettlement and marks the
  # contract executed. Idempotent on an already-executed settlement.
  #
  # Distribution of peg_pot to the individual holders is Workstream B.3; this
  # service stops at broadcasting the CET that releases the pot to the peg side.
  class SettlementService
    class Error < StandardError; end

    Result = Data.define(:dlc_settlement, :cet_txid, :outcome, :peg_pot_sats, :investor_sats)

    def self.call(budget:, end_btc_eur_rate:, oracle: nil, node: nil)
      new(budget:, end_btc_eur_rate:, oracle:, node:).call
    end

    def initialize(budget:, end_btc_eur_rate:, oracle: nil, node: nil)
      @budget = budget
      @end_btc_eur_rate = end_btc_eur_rate
      @oracle = oracle || Config.oracle_client
      @node = node || NodeClient.default
    end

    def call
      contract = budget.dlc_contract
      raise Error, I18n.t("services.dlc.settlement.missing_contract", budget_id: budget.id) if contract.nil?

      existing = budget.dlc_settlement
      return result_for(existing) if existing&.executed?

      outcome = end_btc_eur_rate.to_i
      attestation = oracle.attest_numeric(
        event_id: contract.oracle_event_id,
        outcome: outcome,
        maturity_epoch: contract.maturity_epoch
      )
      execution = node.execute_contract(
        contract_id: contract.ddk_contract_id,
        attestation: attestation.hex,
        close_package: contract.close_package_payload
      )

      settlement = DlcSettlement.create!(
        budget: budget,
        dlc_contract: contract,
        cet_txid: execution.cet_txid,
        outcome: outcome,
        attestation: attestation.hex,
        peg_pot_sats: execution.peg_sats,
        investor_sats: execution.investor_sats,
        status: :executed,
        executed_at: Time.current
      )
      contract.update!(status: :executed)

      result_for(settlement)
    rescue OracleClient::Error, NodeClient::Error => e
      raise Error, I18n.t("services.dlc.settlement.failed", message: e.message)
    end

    private

    attr_reader :budget, :end_btc_eur_rate, :oracle, :node

    def result_for(settlement)
      Result.new(
        dlc_settlement: settlement,
        cet_txid: settlement.cet_txid,
        outcome: settlement.outcome,
        peg_pot_sats: settlement.peg_pot_sats,
        investor_sats: settlement.investor_sats
      )
    end
  end
end
