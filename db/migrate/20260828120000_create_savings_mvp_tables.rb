# frozen_string_literal: true

class CreateSavingsMvpTables < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_accounts do |t|
      t.string :name, null: false
      t.string :iban, null: false
      t.integer :balance_eur_cents, default: 0, null: false
      t.string :btc_receive_address
      t.boolean :default, default: false, null: false
      t.timestamps
    end
    add_index :bank_accounts, :iban, unique: true

    create_table :funding_requests do |t|
      t.integer :user_id, null: false
      t.integer :budget_id
      t.integer :role, null: false
      t.integer :status, default: 0, null: false
      t.integer :amount_eur_cents, null: false
      t.integer :remaining_eur_cents, null: false
      t.integer :payout_mode, default: 0, null: false
      t.string :payout_iban
      t.string :receive_address, null: false
      t.string :change_address
      t.string :identity_pubkey
      t.json :funding_inputs
      t.string :display_name
      t.timestamps
    end
    add_index :funding_requests, :user_id
    add_index :funding_requests, :budget_id
    add_index :funding_requests, %i[role status]

    create_table :bank_transfers do |t|
      t.integer :bank_account_id, null: false
      t.integer :funding_request_id
      t.integer :budget_id
      t.integer :direction, null: false
      t.integer :amount_eur_cents, null: false
      t.string :counterparty_iban
      t.string :btc_txid
      t.integer :btc_sats
      t.integer :status, default: 0, null: false
      t.timestamps
    end
    add_index :bank_transfers, :bank_account_id
    add_index :bank_transfers, :funding_request_id

    add_column :budgets, :saver_payout_mode, :integer, default: 0, null: false
    add_column :budgets, :saver_payout_iban, :string
    add_column :budgets, :saver_payout_address, :string
    add_column :budgets, :investor_payout_mode, :integer, default: 0, null: false
    add_column :budgets, :saver_funding_request_id, :integer
    add_column :budgets, :investor_funding_request_id, :integer
  end
end
