# frozen_string_literal: true

class CreateDlcTables < ActiveRecord::Migration[8.1]
  def change
    create_table :dlc_contracts do |t|
      t.references :budget, null: false, foreign_key: true, index: { unique: true }
      t.string :oracle_event_id, null: false
      t.text :oracle_announcement
      t.string :ddk_contract_id
      t.string :funding_txid
      t.integer :funding_vout
      t.integer :num_digits
      t.bigint :maturity_epoch
      t.string :unit
      t.bigint :peg_collateral_sats
      t.bigint :investor_collateral_sats
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    create_table :dlc_settlements do |t|
      t.references :budget, null: false, foreign_key: true, index: { unique: true }
      t.references :dlc_contract, null: false, foreign_key: true
      t.string :cet_txid
      t.bigint :outcome
      t.text :attestation
      t.bigint :peg_pot_sats
      t.bigint :investor_sats
      t.integer :status, null: false, default: 0
      t.datetime :executed_at

      t.timestamps
    end
  end
end
