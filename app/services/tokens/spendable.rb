# frozen_string_literal: true

module Tokens
  module Spendable
    Position = Data.define(:budget, :balance_cents)

    module_function

    def positions_for(user)
      active_budgets_for(user).filter_map do |budget|
        balance = Rgb::BalanceService.settled(user: user, budget: budget)
        next if balance <= 0

        Position.new(budget: budget, balance_cents: balance)
      end.sort_by { |position| -position.budget.updated_at.to_i }
    end

    def fund_positions_for(user)
      fund_budget_ids = (
        user.borrowed_budgets.where.not(status: :pending).pluck(:id) +
        user.received_token_transfers.distinct.pluck(:budget_id)
      ).uniq

      positions_for(user).select { |position| fund_budget_ids.include?(position.budget.id) }
    end

    def accounts_for(user)
      positions_for(user)
    end

    def total_cents_for(user)
      positions_for(user).sum(&:balance_cents)
    end

    def active_budgets_for(user)
      budget_ids = user.rgb_assignments.joins(:budget).merge(Budget.active).pluck(:budget_id)
      budget_ids |= user.token_accounts.joins(:budget).merge(Budget.active).pluck(:budget_id)
      Budget.where(id: budget_ids.uniq)
    end
    private_class_method :active_budgets_for
  end
end
