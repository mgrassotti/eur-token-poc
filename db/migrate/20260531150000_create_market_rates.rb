# frozen_string_literal: true

class CreateMarketRates < ActiveRecord::Migration[8.1]
  def change
    create_table :market_rates do |t|
      t.decimal :btc_eur_per_btc, precision: 16, scale: 2
      t.references :set_by, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
