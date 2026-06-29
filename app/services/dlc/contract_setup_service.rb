# frozen_string_literal: true

module Dlc
  # Activation hook: announce the maturity price event on the oracle and fund
  # the 2-of-2 DLC contract on the ddk node, persisting the result as a
  # DlcContract. Idempotent — returns the existing contract if already set up.
  #
  # Gated by Dlc::Config.enabled? at the call site (L1::ProvisionEscrowService);
  # while disabled the legacy 2-of-3 escrow remains the settlement mechanism.
  class ContractSetupService
    class Error < StandardError; end

    def self.call(budget:, oracle: nil, node: nil)
      new(budget:, oracle:, node:).call
    end

    def initialize(budget:, oracle: nil, node: nil)
      @budget = budget
      @oracle = oracle || Config.oracle_client
      @node = node || NodeClient.default
    end

    def call
      return budget.dlc_contract if budget.dlc_contract.present?
      raise Error, "Budget peg mancante per il DLC" unless budget.peg_set?

      announcement = oracle.announce_numeric(event_id: event_id, maturity_epoch: maturity_epoch)
      num_digits = announcement.num_digits || Config.num_digits

      points = PayoutCurve.for(budget: budget, num_digits: num_digits)
      contract = node.create_contract(
        oracle_announcement: announcement.hex,
        payouts: points.map { |p| { outcome: p.outcome, peg_sats: p.peg_sats, investor_sats: p.investor_sats } },
        peg_collateral_sats: budget.borrower_locked_sats,
        investor_collateral_sats: budget.investor_locked_sats,
        refund_locktime: budget.refund_locktime_height,
        contract_id: event_id
      )

      DlcContract.create!(
        budget: budget,
        oracle_event_id: event_id,
        oracle_announcement: announcement.hex,
        ddk_contract_id: contract.contract_id,
        funding_txid: contract.funding_txid,
        funding_vout: contract.funding_vout,
        num_digits: num_digits,
        maturity_epoch: maturity_epoch,
        unit: announcement.unit || Config.price_unit,
        peg_collateral_sats: budget.borrower_locked_sats,
        investor_collateral_sats: budget.investor_locked_sats,
        status: :funded
      )
    rescue OracleClient::Error, NodeClient::Error => e
      raise Error, "Setup DLC fallito: #{e.message}"
    end

    private

    attr_reader :budget, :oracle, :node

    def event_id
      "deal-#{budget.id}"
    end

    # Maturity timestamp the oracle commits to. For Pythia (price-feed oracle)
    # this is a near-future scheduled slot (see Config.oracle_maturity_epoch);
    # otherwise the budget calendar maturity (period_end) is used. Memoized so the
    # same epoch is announced, persisted and later attested.
    def maturity_epoch
      @maturity_epoch ||= Config.oracle_maturity_epoch || budget.period_end.to_time.to_i
    end
  end
end
