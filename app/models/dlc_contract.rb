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

  def close_package_complete?
    sign_package.present? &&
      offerer_adaptor_sigs.present? &&
      acceptor_adaptor_sigs.present? &&
      offerer_refund_sig.present? &&
      acceptor_refund_sig.present?
  end

  def close_package_payload
    return unless close_package_complete?

    {
      "sign_package" => sign_package,
      "offerer_adaptor_sigs" => offerer_adaptor_sigs,
      "acceptor_adaptor_sigs" => acceptor_adaptor_sigs,
      "offerer_refund_sig" => offerer_refund_sig,
      "acceptor_refund_sig" => acceptor_refund_sig
    }
  end

  def record_party_signatures!(role:, adaptor_sigs:, refund_sig:)
    sigs = Array(adaptor_sigs).map(&:to_s)
    raise ArgumentError, "adaptor_sigs required" if sigs.empty?
    raise ArgumentError, "refund_sig required" if refund_sig.blank?

    case role.to_s
    when "offer", "offerer", "peg", "saver", "borrower"
      update!(offerer_adaptor_sigs: sigs, offerer_refund_sig: refund_sig.to_s)
    when "accept", "acceptor", "investor"
      update!(acceptor_adaptor_sigs: sigs, acceptor_refund_sig: refund_sig.to_s)
    else
      raise ArgumentError, "unknown DLC role #{role}"
    end
  end
end
