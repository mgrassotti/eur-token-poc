# frozen_string_literal: true

class BtcAccount < ApplicationRecord
  belongs_to :user

  validates :balance_sats, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
