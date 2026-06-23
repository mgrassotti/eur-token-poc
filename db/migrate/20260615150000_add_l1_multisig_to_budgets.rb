# frozen_string_literal: true

class AddL1MultisigToBudgets < ActiveRecord::Migration[8.1]
  def change
    change_table :budgets, bulk: true do |t|
      t.string :peg_party_pubkey
      t.string :investor_pubkey
      t.string :bot_pubkey
      t.string :escrow_txid
      t.integer :escrow_vout
      t.integer :refund_delay_blocks, null: false, default: 1008
      t.json :recovery_package
    end
  end
end
