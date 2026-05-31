# frozen_string_literal: true

class Budget < ApplicationRecord
  COLLATERAL_MULTIPLIER = 2

  belongs_to :borrower, class_name: "User"
  belongs_to :investor, class_name: "User", optional: true

  has_one :collateral_lock, dependent: :destroy
  has_one :settlement, dependent: :destroy
  has_many :token_accounts, dependent: :destroy
  has_many :token_transfers, dependent: :destroy

  enum :status, { pending: 0, active: 1, settled: 2 }

  validates :amount_eur_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :collateral_eur_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :period_start, :period_end, presence: true
  validate :period_end_after_start

  before_validation :set_default_collateral, on: :create

  scope :awaiting_investor, -> { pending.where(investor_id: nil) }

  def peg_set?
    peg_eur_per_btc.present? && peg_eur_per_btc.positive?
  end

  def amount_eur
    amount_eur_cents / 100.0
  end

  def collateral_eur
    collateral_eur_cents / 100.0
  end

  def collateral_sats_at_peg(peg_rate)
    BtcConversion.eur_cents_to_sats(collateral_eur_cents, peg_rate)
  end

  def minted_token_cents
    token_accounts.sum(:balance_cents)
  end

  private

  def set_default_collateral
    return if amount_eur_cents.blank?

    self.collateral_eur_cents = amount_eur_cents * COLLATERAL_MULTIPLIER
  end

  def period_end_after_start
    return if period_start.blank? || period_end.blank?
    return if period_end >= period_start

    errors.add(:period_end, "must be on or after period start")
  end
end
