# frozen_string_literal: true

class CreateReceiveRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :receive_requests do |t|
      t.string :public_id, null: false
      t.references :user, null: false, foreign_key: true
      t.integer :amount_eur_cents
      t.string :recipient_id, null: false
      t.text :invoice
      t.datetime :expires_at, null: false
      t.datetime :paid_at
      t.integer :paid_by_user_id

      t.timestamps
    end
    add_index :receive_requests, :public_id, unique: true
    add_index :receive_requests, :expires_at
  end
end
