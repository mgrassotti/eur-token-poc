# frozen_string_literal: true

class AddBorrowerLockedSatsToBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :budgets, :borrower_locked_sats, :bigint, null: false, default: 0
  end
end
