# frozen_string_literal: true

module Budgets
  # Stores one party's CET adaptor signatures + refund sig, then finalizes
  # funding once both PSBTs and both DLC signature sets are present.
  class SubmitDlcSignatureService
    class Error < StandardError; end

    def self.call(budget:, funding_address:, adaptor_sigs:, refund_sig:)
      new(budget:, funding_address:, adaptor_sigs:, refund_sig:).call
    end

    def initialize(budget:, funding_address:, adaptor_sigs:, refund_sig:)
      @budget = budget
      @funding_address = funding_address.to_s.strip
      @adaptor_sigs = adaptor_sigs
      @refund_sig = refund_sig
    end

    def call
      raise Error, "deal is not active" unless budget.active?
      raise Error, "DLC contract missing" if budget.dlc_contract.blank?
      raise Error, "sign package missing" if budget.dlc_contract.sign_package.blank?

      role = party_role!
      budget.dlc_contract.record_party_signatures!(
        role: role,
        adaptor_sigs: @adaptor_sigs,
        refund_sig: @refund_sig
      )

      if role == :borrower
        budget.update!(borrower_dlc_signed: true)
      else
        budget.update!(investor_dlc_signed: true)
      end

      maybe_forward_to_node!(role)
      maybe_finalize!
      budget.reload
    rescue ArgumentError => e
      raise Error, e.message
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

    def maybe_forward_to_node!(role)
      node = Dlc::NodeClient.default
      return unless node.available?

      node.submit_adaptor_sigs(
        contract_id: budget.dlc_contract.ddk_contract_id,
        role: role == :borrower ? "offer" : "accept",
        adaptor_sigs: @adaptor_sigs,
        refund_sig: @refund_sig
      )
    rescue Dlc::NodeClient::Error => e
      Rails.logger.warn("DLC adaptor sig forward failed: #{e.message}")
    end

    def maybe_finalize!
      return unless budget.borrower_funding_signed? && budget.investor_funding_signed?
      return unless budget.borrower_dlc_signed? && budget.investor_dlc_signed?
      return if budget.l1_multisig_provisioned?

      FinalizeFundingService.call(budget: budget.reload)
    end
  end
end
