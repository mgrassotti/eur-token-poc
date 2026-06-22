# frozen_string_literal: true

module Budgets
  class ReconcileService
    def self.call(exclude_budget_ids: [])
      new(exclude_budget_ids:).call
    end

    def initialize(exclude_budget_ids: [])
      @exclude_budget_ids = exclude_budget_ids
    end

    def call
      scope = Budget.active.order(:id)
      scope = scope.where.not(id: exclude_budget_ids) if exclude_budget_ids.any?

      scope.flat_map { |budget| InvestorYieldService.call(budget: budget) }
    end

    private

    attr_reader :exclude_budget_ids
  end
end
