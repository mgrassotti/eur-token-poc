class AddEscrowIdentityToBtcAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :btc_accounts, :escrow_identity_wif, :string
    add_column :btc_accounts, :escrow_identity_pubkey, :string
  end
end
