# frozen_string_literal: true

class CreateInvestorYieldPayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :investor_yield_payouts do |t|
      t.references :budget, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.bigint :btc_sats, null: false
      t.decimal :btc_eur_per_btc, precision: 16, scale: 2, null: false
      t.datetime :paid_at, null: false

      t.timestamps
    end
  end
end
