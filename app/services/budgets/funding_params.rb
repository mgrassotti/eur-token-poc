# frozen_string_literal: true

module Budgets
  # Client-supplied UTXOs + addresses for DLC funding (no server UserWallet).
  class FundingParams
    class Error < StandardError; end

    attr_reader :peg_inputs, :investor_inputs, :peg_change_address, :investor_change_address,
                :investor_payout_address, :peg_identity_pubkey, :investor_identity_pubkey

    def self.from_hash(hash)
      h = hash.deep_symbolize_keys
      new(
        peg_inputs: normalize_inputs(h[:peg_inputs] || h[:borrower_inputs]),
        investor_inputs: normalize_inputs(h[:investor_inputs]),
        peg_change_address: h[:peg_change_address] || h[:borrower_change_address],
        investor_change_address: h[:investor_change_address],
        investor_payout_address: h[:investor_payout_address],
        peg_identity_pubkey: h[:peg_identity_pubkey] || h[:borrower_identity_pubkey],
        investor_identity_pubkey: h[:investor_identity_pubkey]
      )
    end

    # Synthetic inputs for unit specs (ProvisionEscrow stubbed — never broadcast).
    def self.synthetic(peg_sats:, investor_sats:)
      new(
        peg_inputs: [ { txid: "aa" * 32, vout: 0, amount_sats: peg_sats } ],
        investor_inputs: [ { txid: "bb" * 32, vout: 0, amount_sats: investor_sats } ],
        peg_change_address: "bcrt1qpegchange000000000000000000000000000000",
        investor_change_address: "bcrt1qinvchange00000000000000000000000000000",
        investor_payout_address: "bcrt1qinvpayout00000000000000000000000000000",
        peg_identity_pubkey: "02#{"a" * 64}",
        investor_identity_pubkey: "02#{"b" * 64}"
      )
    end

    def self.normalize_inputs(raw)
      Array(raw).map do |item|
        h = item.respond_to?(:deep_symbolize_keys) ? item.deep_symbolize_keys : item.to_h.symbolize_keys
        {
          txid: h.fetch(:txid).to_s,
          vout: h.fetch(:vout).to_i,
          amount_sats: h.fetch(:amount_sats).to_i
        }
      end
    end

    def initialize(peg_inputs:, investor_inputs:, peg_change_address:, investor_change_address:,
                   investor_payout_address:, peg_identity_pubkey:, investor_identity_pubkey:)
      @peg_inputs = self.class.normalize_inputs(peg_inputs)
      @investor_inputs = self.class.normalize_inputs(investor_inputs)
      @peg_change_address = peg_change_address.to_s
      @investor_change_address = investor_change_address.to_s
      @investor_payout_address = investor_payout_address.to_s
      @peg_identity_pubkey = peg_identity_pubkey.to_s
      @investor_identity_pubkey = investor_identity_pubkey.to_s
    end

    def peg_total_sats
      peg_inputs.sum { |i| i[:amount_sats] }
    end

    def investor_total_sats
      investor_inputs.sum { |i| i[:amount_sats] }
    end

    def validate_presence!
      raise Error, "peg_inputs required" if peg_inputs.empty?
      raise Error, "investor_inputs required" if investor_inputs.empty?
      raise Error, "peg_change_address required" if peg_change_address.blank?
      raise Error, "investor_change_address required" if investor_change_address.blank?
      raise Error, "investor_payout_address required" if investor_payout_address.blank?
      raise Error, "peg_identity_pubkey required" if peg_identity_pubkey.blank?
      raise Error, "investor_identity_pubkey required" if investor_identity_pubkey.blank?
    end
  end
end
