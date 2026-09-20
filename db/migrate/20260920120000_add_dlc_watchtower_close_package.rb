# frozen_string_literal: true

class AddDlcWatchtowerClosePackage < ActiveRecord::Migration[8.1]
  def change
    add_column :dlc_contracts, :sign_package, :json
    add_column :dlc_contracts, :offerer_adaptor_sigs, :json
    add_column :dlc_contracts, :acceptor_adaptor_sigs, :json
    add_column :dlc_contracts, :offerer_refund_sig, :text
    add_column :dlc_contracts, :acceptor_refund_sig, :text
    add_column :dlc_contracts, :direct_payout, :boolean, default: true, null: false

    add_column :budgets, :borrower_dlc_signed, :boolean, default: false, null: false
    add_column :budgets, :investor_dlc_signed, :boolean, default: false, null: false
  end
end
