# frozen_string_literal: true

class TokenTransfer < ApplicationRecord
  belongs_to :budget
  belongs_to :from_user, class_name: "User"
  belongs_to :to_user, class_name: "User"

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validate :different_users

  def amount_eur
    amount_cents / 100.0
  end

  private

  def different_users
    return if from_user_id != to_user_id

    errors.add(:to_user, "must be different from sender")
  end
end
