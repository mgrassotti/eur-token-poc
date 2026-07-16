# frozen_string_literal: true

class AddReserveReceiveAddressToBtcAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :btc_accounts, :reserve_receive_address, :string
    add_index :btc_accounts, :reserve_receive_address, unique: true, where: "reserve_receive_address IS NOT NULL"
  end
end
