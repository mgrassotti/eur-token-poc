# frozen_string_literal: true

class AddRlnFieldsToBtcAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :btc_accounts, :rln_node_url, :string
    add_column :btc_accounts, :rln_token, :string
    add_column :btc_accounts, :node_pubkey, :string
  end
end
