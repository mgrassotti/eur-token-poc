# frozen_string_literal: true

class CreateRgbAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :rgb_assignments do |t|
      t.references :budget, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :assignment_id, null: false
      t.string :holder_pubkey, null: false
      t.integer :notional_share_cents, null: false, default: 0
      t.string :parent_assignment_id

      t.timestamps
    end

    add_index :rgb_assignments, :assignment_id, unique: true
    add_index :rgb_assignments, %i[budget_id user_id], unique: true
  end
end
