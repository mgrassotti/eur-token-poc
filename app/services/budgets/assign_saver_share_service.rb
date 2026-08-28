# frozen_string_literal: true

module Budgets
  # Bookkeeping share for the saver (no RGB mint). Settlement treats this as
  # the single 100% FloorEUR holder.
  class AssignSaverShareService
    def self.call(budget:)
      TokenAccount.find_or_initialize_by(budget: budget, user: budget.borrower).tap do |account|
        account.balance_cents = budget.amount_eur_cents
        account.save!
      end
    end
  end
end
