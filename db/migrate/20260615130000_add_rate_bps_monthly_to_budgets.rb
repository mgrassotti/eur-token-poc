# frozen_string_literal: true

class AddRateBpsMonthlyToBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :budgets, :rate_bps_monthly, :integer, null: false, default: 100
  end
end
