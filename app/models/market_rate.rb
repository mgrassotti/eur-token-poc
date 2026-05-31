# frozen_string_literal: true

class MarketRate < ApplicationRecord
  belongs_to :set_by, class_name: "User", optional: true

  validates :btc_eur_per_btc, numericality: { greater_than: 0 }, allow_nil: true

  def self.current
    first_or_create!
  end

  def set?
    btc_eur_per_btc.present? && btc_eur_per_btc.positive?
  end
end
