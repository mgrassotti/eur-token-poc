# frozen_string_literal: true

module Budgets
  # Finalizes a partially-signed DLC funding PSBT: broadcast, record lock, RGB.
  class FinalizeFundingService
    class Error < StandardError; end

    def self.call(budget:)
      new(budget:).call
    end

    def initialize(budget:)
      @budget = budget
      @global_client = L1::Bitcoind::Client.new
    end

    def call
      raise Error, "deal is not active" unless budget.active?
      raise Error, "funding PSBT missing" if budget.funding_psbt.blank?
      raise Error, "both parties must sign the funding PSBT" unless budget.borrower_funding_signed? && budget.investor_funding_signed?
      raise Error, "both parties must sign the DLC CET set" unless budget.borrower_dlc_signed? && budget.investor_dlc_signed?
      return budget if budget.l1_multisig_provisioned?

      dlc = budget.dlc_contract
      raise Error, "DLC contract missing — accept the deal first" if dlc.blank?

      finalized = @global_client.call("finalizepsbt", budget.funding_psbt)
      raise Error, "funding PSBT incomplete" unless finalized["complete"]

      hex = finalized.fetch("hex")
      txid = @global_client.call("sendrawtransaction", hex)
      if dlc.funding_txid.present? && txid != dlc.funding_txid
        raise Error, "funding txid mismatch (#{txid} != #{dlc.funding_txid})"
      end

      L1::RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET).mine_blocks(1)

      package = budget.recovery_package&.deep_dup || {}
      package["escrow"] = {
        "outpoint" => "#{txid}:#{dlc.funding_vout}",
        "peg_party_pubkey" => budget.peg_party_pubkey,
        "investor_pubkey" => budget.investor_pubkey,
        "amount_sats" => budget.borrower_locked_sats + budget.investor_locked_sats,
        "investor_payout_address" => budget.investor_payout_address,
        "note" => "Fase 1 — funding 2-of-2 DLC from on-device signed PSBT"
      }

      budget.update!(
        funding_tx_hex: hex,
        escrow_txid: txid,
        escrow_vout: dlc.funding_vout,
        recovery_package: package
      )
      dlc.update!(status: :funded, funding_txid: txid)

      Rgb::IssueService.call(budget: budget.reload)
      budget.reload
    rescue L1::Bitcoind::Error => e
      raise Error, "funding finalize failed: #{e.message}"
    end

    private

    attr_reader :budget
  end
end
