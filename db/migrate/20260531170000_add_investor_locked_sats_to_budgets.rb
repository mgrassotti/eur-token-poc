# frozen_string_literal: true

class AddInvestorLockedSatsToBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :budgets, :investor_locked_sats, :bigint, null: false, default: 0
  end
end
