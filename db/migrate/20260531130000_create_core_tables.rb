# frozen_string_literal: true

class CreateCoreTables < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false

      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :btc_accounts do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.bigint :balance_sats, null: false, default: 0

      t.timestamps
    end

    create_table :budgets do |t|
      t.references :borrower, null: false, foreign_key: { to_table: :users }
      t.references :investor, foreign_key: { to_table: :users }
      t.integer :amount_eur_cents, null: false
      t.integer :collateral_eur_cents, null: false
      t.decimal :peg_eur_per_btc, precision: 16, scale: 2
      t.integer :status, null: false, default: 0
      t.date :period_start, null: false
      t.date :period_end, null: false

      t.timestamps
    end

    create_table :collateral_locks do |t|
      t.references :budget, null: false, foreign_key: true, index: { unique: true }
      t.bigint :amount_sats, null: false
      t.datetime :locked_at, null: false

      t.timestamps
    end

    create_table :token_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :budget, null: false, foreign_key: true
      t.integer :balance_cents, null: false, default: 0

      t.timestamps
    end
    add_index :token_accounts, %i[user_id budget_id], unique: true

    create_table :token_transfers do |t|
      t.references :budget, null: false, foreign_key: true
      t.references :from_user, null: false, foreign_key: { to_table: :users }
      t.references :to_user, null: false, foreign_key: { to_table: :users }
      t.integer :amount_cents, null: false

      t.timestamps
    end

    create_table :settlements do |t|
      t.references :budget, null: false, foreign_key: true, index: { unique: true }
      t.decimal :end_btc_eur_rate, precision: 16, scale: 2, null: false
      t.bigint :total_btc_to_holders_sats, null: false
      t.bigint :btc_to_investor_sats, null: false
      t.datetime :executed_at, null: false

      t.timestamps
    end
  end
end
