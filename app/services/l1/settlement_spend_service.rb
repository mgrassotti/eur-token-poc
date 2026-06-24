# frozen_string_literal: true

module L1
  # @deprecated Prefer {L1::SettlementPsbtService} — mantiene compatibilità con chiamate esistenti.
  class SettlementSpendService
    class Error < SettlementPsbtService::Error; end

    HolderPayout = SettlementTxBuilder::HolderPayout

    def self.call(budget:, payoff:, holder_payouts:)
      SettlementPsbtService.call(budget:, payoff:, holder_payouts:)
    rescue SettlementPsbtService::Error => e
      raise Error, e.message
    end
  end
end
