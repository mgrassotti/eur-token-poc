# frozen_string_literal: true

class InvestorYieldPayout < ApplicationRecord
  belongs_to :budget
  belongs_to :user

  validates :btc_sats, numericality: { only_integer: true, greater_than: 0 }
  validates :btc_eur_per_btc, numericality: { greater_than: 0 }
  validates :paid_at, presence: true
end
