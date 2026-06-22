# frozen_string_literal: true

module Tokens
  module Spendable
    module_function

    def accounts_for(user)
      user.token_accounts
          .joins(:budget)
          .merge(Budget.active)
          .where("token_accounts.balance_cents > 0")
          .includes(:budget)
          .order("token_accounts.updated_at DESC")
    end

    def total_cents_for(user)
      accounts_for(user).sum(:balance_cents)
    end
  end
end
