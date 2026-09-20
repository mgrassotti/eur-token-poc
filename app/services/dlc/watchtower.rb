# frozen_string_literal: true

module Dlc
  # Watchtower: broadcast a pre-signed CET (or refund) without party keys.
  # Relies on the close package uploaded at activation (adaptor sigs + refund).
  class Watchtower
    class Error < StandardError; end

    Result = Data.define(:executed, :refunded)

    def self.call
      new.call
    end

    def call
      Result.new(executed: execute_mature, refunded: refund_overdue)
    end

    def self.refund_overdue
      new.refund_overdue
    end

    def self.execute_mature
      new.execute_mature
    end

    # Broadcast the attested CET from the stored close package (no party keys).
    def execute_mature
      executed = []
      rate = MarketRate.current.btc_eur_per_btc
      return executed unless rate.present? && rate.positive?

      DlcContract.funded.includes(:budget).find_each do |contract|
        budget = contract.budget
        next unless budget&.active?
        next unless budget.ready_for_settlement?
        next if budget.dlc_settlement&.executed?
        next unless contract.close_package_complete?

        SettlementService.call(budget: budget, end_btc_eur_rate: rate)
        executed << contract.reload
      rescue SettlementService::Error => e
        Rails.logger.warn("Watchtower CET failed for contract #{contract.id}: #{e.message}")
      end
      executed
    end

    def refund_overdue
      refunded = []
      height = ChainState.block_height
      DlcContract.funded.includes(:budget).find_each do |contract|
        budget = contract.budget
        next unless budget&.active?
        next if budget.dlc_settlement&.executed?
        next unless contract.close_package_complete?
        next unless height >= budget.refund_locktime_height

        result = NodeClient.default.refund_contract(
          contract_id: contract.ddk_contract_id,
          close_package: contract.close_package_payload
        )
        contract.update!(status: :refunded)
        refunded << result
      rescue NodeClient::Error => e
        Rails.logger.warn("Watchtower refund failed for contract #{contract.id}: #{e.message}")
      end
      refunded
    end
  end
end
