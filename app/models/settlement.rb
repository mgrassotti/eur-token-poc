# frozen_string_literal: true

class Settlement < ApplicationRecord
  belongs_to :budget

  validates :end_btc_eur_rate, numericality: { greater_than: 0 }
  validates :total_btc_to_holders_sats, :btc_to_investor_sats, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :executed_at, presence: true
end
