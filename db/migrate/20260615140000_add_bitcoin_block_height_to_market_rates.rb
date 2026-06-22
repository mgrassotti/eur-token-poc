# frozen_string_literal: true

class AddBitcoinBlockHeightToMarketRates < ActiveRecord::Migration[8.1]
  def change
    add_column :market_rates, :bitcoin_block_height, :bigint, null: false, default: 0
  end
end
