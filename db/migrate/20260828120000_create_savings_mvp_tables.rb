# frozen_string_literal: true

class CreateSavingsMvpTables < ActiveRecord::Migration[8.1]
  # SQLite auto-commits DDL, so a failed first run can leave bank_accounts in
  # place while this version stays pending. Re-running must be a no-op.
  def up
    create_table :bank_accounts, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :iban, null: false
      t.integer :balance_eur_cents, default: 0, null: false
      t.string :btc_receive_address
      t.boolean :default, default: false, null: false
      t.timestamps
    end
    add_index :bank_accounts, :iban, unique: true, if_not_exists: true

    create_table :funding_requests, if_not_exists: true do |t|
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
    add_index :funding_requests, :user_id, if_not_exists: true
    add_index :funding_requests, :budget_id, if_not_exists: true
    add_index :funding_requests, %i[role status], if_not_exists: true

    create_table :bank_transfers, if_not_exists: true do |t|
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
    add_index :bank_transfers, :bank_account_id, if_not_exists: true
    add_index :bank_transfers, :funding_request_id, if_not_exists: true

    add_savings_budget_columns!
  end

  def down
    remove_column :budgets, :investor_funding_request_id if column_exists?(:budgets, :investor_funding_request_id)
    remove_column :budgets, :saver_funding_request_id if column_exists?(:budgets, :saver_funding_request_id)
    remove_column :budgets, :investor_payout_mode if column_exists?(:budgets, :investor_payout_mode)
    remove_column :budgets, :saver_payout_address if column_exists?(:budgets, :saver_payout_address)
    remove_column :budgets, :saver_payout_iban if column_exists?(:budgets, :saver_payout_iban)
    remove_column :budgets, :saver_payout_mode if column_exists?(:budgets, :saver_payout_mode)

    drop_table :bank_transfers, if_exists: true
    drop_table :funding_requests, if_exists: true
    drop_table :bank_accounts, if_exists: true
  end

  private

  def add_savings_budget_columns!
    add_column :budgets, :saver_payout_mode, :integer, default: 0, null: false unless column_exists?(:budgets, :saver_payout_mode)
    add_column :budgets, :saver_payout_iban, :string unless column_exists?(:budgets, :saver_payout_iban)
    add_column :budgets, :saver_payout_address, :string unless column_exists?(:budgets, :saver_payout_address)
    add_column :budgets, :investor_payout_mode, :integer, default: 0, null: false unless column_exists?(:budgets, :investor_payout_mode)
    add_column :budgets, :saver_funding_request_id, :integer unless column_exists?(:budgets, :saver_funding_request_id)
    add_column :budgets, :investor_funding_request_id, :integer unless column_exists?(:budgets, :investor_funding_request_id)
  end
end
