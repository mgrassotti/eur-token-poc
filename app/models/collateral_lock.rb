# frozen_string_literal: true

class CollateralLock < ApplicationRecord
  belongs_to :budget

  validates :amount_sats, numericality: { only_integer: true, greater_than: 0 }
  validates :locked_at, presence: true
end
