# frozen_string_literal: true

class AddRgbLibFields < ActiveRecord::Migration[8.1]
  def change
    add_column :btc_accounts, :rgb_mnemonic, :string
    add_column :btc_accounts, :rgb_wallet_id, :string
    add_column :budgets, :rgb_asset_id, :string
    add_column :rgb_assignments, :rgb_asset_id, :string
    add_column :rgb_assignments, :rgb_recipient_id, :string
    add_column :token_transfers, :rgb_transfer_txid, :string
  end
end
