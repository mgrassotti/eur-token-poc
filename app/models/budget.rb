# frozen_string_literal: true

class Budget < ApplicationRecord
  # Borrower 1× (alla creazione) + investitore 1× (all'attivazione) = pool 2× il budget.
  # Settlement FloorEUR: liability € + interesse, liquidato in sats allo spot (PAYOFF-SPEC).
  INVESTOR_COLLATERAL_MULTIPLIER = 1
  INVESTOR_YIELD_LTV_THRESHOLD = 0.3
  LIQUIDATION_LTV_THRESHOLD = 0.9
  BLOCKS_PER_MONTH = 4356
  DAYS_PER_SYMBOLIC_MONTH = 30.25
  MIN_HEDGE_TO_PEG_RATIO = 2

  belongs_to :borrower, class_name: "User"
  belongs_to :investor, class_name: "User", optional: true

  has_one :collateral_lock, dependent: :destroy
  has_one :settlement, dependent: :destroy
  has_many :token_accounts, dependent: :destroy
  has_many :token_transfers, dependent: :destroy
  has_many :investor_yield_payouts, dependent: :destroy

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

  # MVP: notional € = importo budget (PAYOFF-SPEC §1, §9).
  def notional_eur_cents
    amount_eur_cents
  end

  def months_elapsed(at_height: ChainState.block_height)
    return symbolic_months_duration unless genesis_block_height

    blocks_elapsed = [at_height - genesis_block_height, 0].max
    blocks_elapsed / BLOCKS_PER_MONTH
  end

  def symbolic_months_duration
    end_months = period_end.year * 12 + period_end.month
    start_months = period_start.year * 12 + period_start.month
    end_months - start_months
  end

  def blocks_remaining
    return unless maturity_block_height

    [maturity_block_height - ChainState.block_height, 0].max
  end

  def ready_for_settlement?
    maturity_block_height.present? && ChainState.block_height >= maturity_block_height
  end

  ESTIMATED_SETTLEMENT_FEE_SATS = 5_000

  def peg_collateral_sats
    borrower_locked_sats
  end

  def hedge_collateral_sats
    investor_locked_sats
  end

  def hedge_collateral_meets_floor?
    peg_collateral_sats.positive? && hedge_collateral_sats >= MIN_HEDGE_TO_PEG_RATIO * peg_collateral_sats
  end

  def pool_sats
    collateral_lock&.amount_sats.to_i
  end

  def pool_collateral_eur(btc_eur_per_btc)
    return unless btc_eur_per_btc.to_d.positive?

    BtcConversion.sats_to_eur(pool_sats, btc_eur_per_btc)
  end

  # EURT in circolazione / valore collateral del deal al cambio corrente.
  def loan_to_value_ratio(btc_eur_per_btc)
    collateral_eur = pool_collateral_eur(btc_eur_per_btc)
    return if collateral_eur.nil? || collateral_eur.zero?

    tokens_eur = minted_token_cents / 100.0
    return 0.0 if tokens_eur.zero?

    tokens_eur / collateral_eur
  end

  def liquidation_threshold_reached?(btc_eur_per_btc)
    ltv = loan_to_value_ratio(btc_eur_per_btc)
    ltv.present? && ltv >= LIQUIDATION_LTV_THRESHOLD
  end

  def yield_eligible?(btc_eur_per_btc)
    ltv = loan_to_value_ratio(btc_eur_per_btc)
    ltv.present? && ltv < INVESTOR_YIELD_LTV_THRESHOLD
  end

  private

  def set_default_collateral
    return if amount_eur_cents.blank?

    self.collateral_eur_cents = amount_eur_cents * INVESTOR_COLLATERAL_MULTIPLIER
  end

  def period_end_after_start
    return if period_start.blank? || period_end.blank?
    return if period_end >= period_start

    errors.add(:period_end, "must be on or after period start")
  end
end
