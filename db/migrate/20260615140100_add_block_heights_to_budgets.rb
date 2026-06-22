# frozen_string_literal: true

class AddBlockHeightsToBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :budgets, :genesis_block_height, :bigint
    add_column :budgets, :maturity_block_height, :bigint
  end
end
