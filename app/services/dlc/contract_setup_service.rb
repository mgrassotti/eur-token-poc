# frozen_string_literal: true

module Dlc
  # Funds the 2-of-2 numeric DLC from client-supplied UTXOs (BDK / on-device).
  # Fund keys stay at the dlc-rs sidecar; only P2WPKH funding inputs are signed
  # by the parties (mobile BDK or auto_sign_wallets in regtest).
  class ContractSetupService
    class Error < StandardError; end

    FUNDING_FEE_BUFFER_SATS = 10_000

    def self.call(budget:, oracle: nil, node: nil, auto_sign_wallets: nil)
      new(budget:, oracle:, node:, auto_sign_wallets:).call
    end

    def initialize(budget:, oracle: nil, node: nil, auto_sign_wallets: nil)
      @budget = budget
      @oracle = oracle || Config.oracle_client
      @node = node || NodeClient.default
      @global_client = L1::Bitcoind::Client.new
      @auto_sign_wallets = auto_sign_wallets
    end

    def call
      return budget.dlc_contract if budget.dlc_contract.present?
      raise Error, I18n.t("services.dlc.contract_setup.missing_peg") unless budget.peg_set?

      peg_inputs = normalize_inputs(budget.reserved_outpoints)
      investor_inputs = normalize_inputs(budget.investor_funding_inputs)
      raise Error, "borrower funding inputs missing" if peg_inputs.empty?
      raise Error, "investor funding inputs missing" if investor_inputs.empty?
      raise Error, "borrower change address missing" if budget.borrower_change_address.blank?
      raise Error, "investor change address missing" if budget.investor_change_address.blank?
      raise Error, "investor payout address missing" if budget.investor_payout_address.blank?

      announcement = oracle.announce_numeric(event_id: event_id, maturity_epoch: maturity_epoch)
      num_digits = announcement.num_digits || Config.num_digits

      peg_sats = budget.borrower_locked_sats
      investor_sats = budget.investor_locked_sats

      points = PayoutCurve.for(budget: budget, num_digits: num_digits)
      contract = node.create_contract(
        oracle_announcement: announcement.hex,
        payouts: points.map { |p| { outcome: p.outcome, peg_sats: p.peg_sats, investor_sats: p.investor_sats } },
        peg_collateral_sats: peg_sats,
        investor_collateral_sats: investor_sats,
        refund_locktime: budget.refund_locktime_height,
        peg_inputs: peg_inputs,
        investor_inputs: investor_inputs,
        peg_change_address: budget.borrower_change_address,
        investor_change_address: budget.investor_change_address,
        investor_payout_address: budget.investor_payout_address,
        contract_id: event_id
      )

      funding_psbt = build_funding_psbt!(contract)
      budget.update!(
        funding_tx_hex: contract.funding_tx_hex,
        funding_psbt: funding_psbt,
        borrower_funding_signed: false,
        investor_funding_signed: false
      )

      if @auto_sign_wallets.present?
        broadcast_with_wallets!(contract, @auto_sign_wallets)
        record_collateral_lock!(contract)
        return create_dlc_record!(contract, announcement, num_digits, peg_sats, investor_sats, status: :funded)
      end

      # Mobile path: persist announced contract + PSBT; wait for funding_signatures.
      create_dlc_record!(contract, announcement, num_digits, peg_sats, investor_sats, status: :announced)
    rescue OracleClient::Error, NodeClient::Error => e
      raise Error, I18n.t("services.dlc.contract_setup.setup_failed", message: e.message)
    rescue L1::Bitcoind::Error => e
      raise Error, I18n.t("services.dlc.contract_setup.funding_failed", message: e.message)
    end

    private

    attr_reader :budget, :oracle, :node

    def normalize_inputs(raw)
      Array(raw).map do |item|
        h = item.respond_to?(:deep_symbolize_keys) ? item.deep_symbolize_keys : item.to_h.symbolize_keys
        {
          txid: h.fetch(:txid).to_s,
          vout: h.fetch(:vout).to_i,
          amount_sats: h.fetch(:amount_sats).to_i
        }
      end
    end

    def build_funding_psbt!(contract)
      raise Error, I18n.t("services.dlc.contract_setup.missing_funding_hex") if contract.funding_tx_hex.blank?

      # permitsigdata must be a bool (not []); iswitness inferred when omitted.
      psbt = @global_client.call("converttopsbt", contract.funding_tx_hex, false)
      # Embed witness UTXOs so BDK can sign without a bitcoind wallet.
      utxoupdate_with_inputs!(psbt)
    end

    def utxoupdate_with_inputs!(psbt)
      descriptors = funding_input_addr_descriptors
      return psbt if descriptors.empty?

      @global_client.call("utxoupdatepsbt", psbt, descriptors)
    rescue L1::Bitcoind::Error
      psbt
    end

    def funding_input_addr_descriptors
      inputs = normalize_inputs(budget.reserved_outpoints) + normalize_inputs(budget.investor_funding_inputs)
      inputs.filter_map do |op|
        utxo = @global_client.call("gettxout", op[:txid], op[:vout])
        next if utxo.blank?

        address = utxo.dig("scriptPubKey", "address")
        next if address.blank?

        info = @global_client.call("getdescriptorinfo", "addr(#{address})")
        { "desc" => info.fetch("descriptor"), "range" => 0 }
      end
    end

    def broadcast_with_wallets!(contract, wallets)
      peg_wallet, investor_wallet = wallets
      raise Error, I18n.t("services.dlc.contract_setup.missing_funding_hex") if contract.funding_tx_hex.blank?

      signed = peg_wallet.client.call("signrawtransactionwithwallet", contract.funding_tx_hex)
      signed = investor_wallet.client.call("signrawtransactionwithwallet", signed.fetch("hex"))
      raise Error, I18n.t("services.dlc.contract_setup.incomplete_funding") unless signed.fetch("complete")

      hex = signed.fetch("hex")
      txid = @global_client.call("sendrawtransaction", hex)
      if contract.funding_txid.present? && txid != contract.funding_txid
        raise Error, I18n.t("services.dlc.contract_setup.changed_txid", txid: txid, expected_txid: contract.funding_txid)
      end

      L1::RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET).mine_blocks(1)
      budget.update!(
        funding_tx_hex: hex,
        borrower_funding_signed: true,
        investor_funding_signed: true
      )
      txid
    end

    def record_collateral_lock!(contract)
      package = budget.recovery_package&.deep_dup || {}
      package["escrow"] = {
        "outpoint" => "#{contract.funding_txid}:#{contract.funding_vout}",
        "peg_party_pubkey" => budget.peg_party_pubkey,
        "investor_pubkey" => budget.investor_pubkey,
        "amount_sats" => budget.borrower_locked_sats + budget.investor_locked_sats,
        "investor_payout_address" => budget.investor_payout_address,
        "note" => "Fase 1 — il funding 2-of-2 del DLC È il lock del collateral"
      }

      budget.update!(
        escrow_txid: contract.funding_txid,
        escrow_vout: contract.funding_vout,
        refund_delay_blocks: Budget::REFUND_DELAY_BLOCKS,
        recovery_package: package
      )
      budget.reload
    end

    def create_dlc_record!(contract, announcement, num_digits, peg_sats, investor_sats, status:)
      DlcContract.create!(
        budget: budget,
        oracle_event_id: event_id,
        oracle_announcement: announcement.hex,
        ddk_contract_id: contract.contract_id,
        funding_txid: contract.funding_txid,
        funding_vout: contract.funding_vout,
        num_digits: num_digits,
        maturity_epoch: maturity_epoch,
        unit: announcement.unit || Config.price_unit,
        peg_collateral_sats: peg_sats,
        investor_collateral_sats: investor_sats,
        status: status
      )
    end

    def event_id
      "deal-#{budget.id}"
    end

    def maturity_epoch
      @maturity_epoch ||= Config.oracle_maturity_epoch || budget.period_end.to_time.to_i
    end
  end
end
