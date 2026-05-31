# frozen_string_literal: true

class TokenAccount < ApplicationRecord
  belongs_to :user
  belongs_to :budget

  validates :balance_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def balance_eur
    balance_cents / 100.0
  end
end
