# frozen_string_literal: true

module Budgets
  class AutoSettleService
    class Error < StandardError; end

    Result = Data.define(:settlements, :blocked_budget_ids)

    def self.call
      new.call
    end

    def call
      settlements = []

      loop do
        budget = Budget.active.order(:created_at).find(&:ready_for_settlement?)
        break unless budget

        rate = MarketRate.current.btc_eur_per_btc
        unless rate.present? && rate.positive?
          raise Error, I18n.t("services.budgets.auto_settle.missing_market_rate")
        end

        settlements << Settlements::ExecuteService.call(
          budget: budget,
          end_btc_eur_rate: rate,
          set_by: User.admins.first
        )
      rescue Settlements::ExecuteService::Error => e
        raise Error, I18n.t("services.budgets.auto_settle.failed", budget_id: budget.id, detail: e.message)
      end

      Dlc::Watchtower.call

      Result.new(
        settlements: settlements,
        blocked_budget_ids: blocked_past_maturity_budget_ids
      )
    end

    private

    def blocked_past_maturity_budget_ids
      Budget.active.order(:created_at).select do |budget|
        budget.maturity_reached? && !budget.ready_for_settlement?
      end.map(&:id)
    end
  end
end
