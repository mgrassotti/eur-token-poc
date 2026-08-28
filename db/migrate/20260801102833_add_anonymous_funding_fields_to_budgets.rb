class AddAnonymousFundingFieldsToBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :budgets, :commitment_psbt, :text
    add_column :budgets, :reserved_outpoints, :json
    add_column :budgets, :funding_address, :string
    add_column :budgets, :funding_psbt, :text
    add_column :budgets, :funding_tx_hex, :text
    add_column :budgets, :borrower_change_address, :string
    add_column :budgets, :investor_change_address, :string
    add_column :budgets, :investor_payout_address, :string
    add_column :budgets, :investor_funding_inputs, :json
    add_column :budgets, :borrower_funding_signed, :boolean, default: false, null: false
    add_column :budgets, :investor_funding_signed, :boolean, default: false, null: false
  end
end
