# frozen_string_literal: true

module Budgets
  # Merges a party-signed funding PSBT. When both sides have signed, finalizes
  # (broadcast + DlcContract + RGB issue).
  class SubmitFundingSignatureService
    class Error < StandardError; end

    def self.call(budget:, funding_address:, signed_psbt:)
      new(budget:, funding_address:, signed_psbt:).call
    end

    def initialize(budget:, funding_address:, signed_psbt:)
      @budget = budget
      @funding_address = funding_address.to_s.strip
      @signed_psbt = signed_psbt.to_s.strip
    end

    def call
      raise Error, "deal is not active" unless budget.active?
      raise Error, "funding PSBT missing — accept the deal first" if budget.funding_psbt.blank?
      raise Error, "signed_psbt required" if @signed_psbt.blank?
      raise Error, "funding already complete" if budget.l1_multisig_provisioned?

      role = party_role!
      combined = combine_psbt!(@signed_psbt)

      attrs = { funding_psbt: combined }
      attrs[:borrower_funding_signed] = true if role == :borrower
      attrs[:investor_funding_signed] = true if role == :investor
      budget.update!(attrs)

      if budget.borrower_funding_signed? && budget.investor_funding_signed?
        FinalizeFundingService.call(budget: budget.reload)
      else
        budget.reload
      end
    end

    private

    attr_reader :budget

    def party_role!
      return :borrower if borrower_addresses.include?(@funding_address)
      return :investor if investor_addresses.include?(@funding_address)

      raise Error, "funding_address does not match borrower or investor"
    end

    def borrower_addresses
      [
        budget.funding_address,
        budget.borrower_change_address,
        budget.borrower.btc_account&.reserve_receive_address
      ].map { |a| a.to_s.strip.presence }.compact.uniq
    end

    def investor_addresses
      [
        budget.investor&.btc_account&.reserve_receive_address,
        budget.investor_change_address,
        budget.investor_payout_address
      ].map { |a| a.to_s.strip.presence }.compact.uniq
    end

    def combine_psbt!(signed)
      client = L1::Bitcoind::Client.new
      client.call("combinepsbt", [budget.funding_psbt, signed])
    rescue L1::Bitcoind::Error => e
      # If combine fails (e.g. same PSBT supersedes), keep the newly signed one.
      raise Error, "failed to combine funding PSBT: #{e.message}" if budget.funding_psbt == signed

      signed
    end
  end
end
