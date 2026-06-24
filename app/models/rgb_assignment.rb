# frozen_string_literal: true

class RgbAssignment < ApplicationRecord
  belongs_to :budget
  belongs_to :user

  validates :assignment_id, presence: true, uniqueness: true
  validates :holder_pubkey, presence: true
  validates :notional_share_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :user_id, uniqueness: { scope: :budget_id }

  scope :with_balance, -> { where("notional_share_cents > 0") }

  def to_position
    Rgb::FloorEurPosition.new(
      assignment_id: assignment_id,
      deal_id: budget_id,
      holder_pubkey: holder_pubkey,
      notional_share: notional_share_cents,
      strike_eur_per_btc: budget.peg_eur_per_btc,
      rate_bps_monthly: budget.rate_bps_monthly,
      blocks_per_month: Budget::BLOCKS_PER_MONTH,
      genesis_height: budget.genesis_block_height,
      maturity_height: budget.maturity_block_height,
      escrow_outpoint: budget.escrow_outpoint
    )
  end
end
