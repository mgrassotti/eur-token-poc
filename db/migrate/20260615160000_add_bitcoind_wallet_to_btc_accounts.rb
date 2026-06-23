# frozen_string_literal: true

class AddBitcoindWalletToBtcAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :btc_accounts, :bitcoind_wallet_name, :string
    add_index :btc_accounts, :bitcoind_wallet_name, unique: true, where: "bitcoind_wallet_name IS NOT NULL"
  end
end
