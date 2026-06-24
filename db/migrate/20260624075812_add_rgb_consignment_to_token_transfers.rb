# frozen_string_literal: true

class AddRgbConsignmentToTokenTransfers < ActiveRecord::Migration[8.1]
  def change
    add_column :token_transfers, :rgb_consignment, :json
  end
end
