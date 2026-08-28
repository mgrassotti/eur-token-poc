# frozen_string_literal: true

class FundingRequest < ApplicationRecord
  belongs_to :user
  belongs_to :budget, optional: true
  has_many :bank_transfers, dependent: :nullify

  enum :role, { saver: 0, investor: 1 }
  enum :status, { awaiting_deposit: 0, queued: 1, matched: 2, cancelled: 3 }
  enum :payout_mode, { keep_btc: 0, reinvest: 1, eur: 2 }

  validates :amount_eur_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :remaining_eur_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :receive_address, presence: true
  validates :payout_iban, presence: true, if: -> { saver? && eur? }
  validate :investor_cannot_choose_eur

  scope :open, -> { where(status: %i[awaiting_deposit queued]) }
  scope :matchable, -> { queued }

  def required_sats(peg = MarketRate.current.btc_eur_per_btc)
    notional = remaining_eur_cents.positive? ? remaining_eur_cents : amount_eur_cents
    BtcConversion.eur_cents_to_sats(notional, peg) +
      Dlc::ContractSetupService::FUNDING_FEE_BUFFER_SATS
  end

  def funding_inputs_list
    Array(funding_inputs).map { |item| item.respond_to?(:deep_symbolize_keys) ? item.deep_symbolize_keys : item }
  end

  def ready_to_match?
    queued? && funding_inputs_list.any? && receive_address.present? && change_address.present?
  end

  private

  def investor_cannot_choose_eur
    return unless investor? && eur?

    errors.add(:payout_mode, :invalid)
  end
end
