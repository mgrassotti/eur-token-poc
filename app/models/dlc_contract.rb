# frozen_string_literal: true

# A DLC contract bound to a budget: the oracle announcement (numeric price
# event) plus the ddk funding outpoint for the 2-of-2 {peg, investor}.
class DlcContract < ApplicationRecord
  belongs_to :budget
  has_one :dlc_settlement, dependent: :destroy

  enum :status, { announced: 0, funded: 1, executed: 2, refunded: 3, failed: 4 }

  validates :oracle_event_id, presence: true

  def funding_outpoint
    return unless funding_txid.present? && !funding_vout.nil?

    "#{funding_txid}:#{funding_vout}"
  end
end
