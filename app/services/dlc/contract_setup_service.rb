# frozen_string_literal: true

module Dlc
  # Activation hook (Fase 1): announce the maturity price event on the oracle and
  # fund the 2-of-2 numeric DLC from the users' REAL L1 reserve UTXOs.
  #
  # The 2-of-2 FUND keys stay at the sidecar (adaptor sigs / sign_cet / refund
  # unchanged), but the funding INPUTS are the peg (borrower) + investor reserve
  # coins, signed here by Ruby with the reserve wallets, and the CET payout/change
  # scriptpubkeys point at real reserve/change addresses. The DLC funding tx IS
  # the collateral lock: there is a single 2-of-2, no orphaned escrow.
  #
  # Called from L1::ProvisionEscrowService. Idempotent — returns the existing
  # contract if already set up.
  class ContractSetupService
    class Error < StandardError; end

    # Extra reserve sats to select beyond each party's collateral so rust-dlc has
    # room for its per-party funding + CET fee share (a few hundred sats at the
    # default fee rate); the remainder returns to the party's change address.
    FUNDING_FEE_BUFFER_SATS = 10_000

    def self.call(budget:, oracle: nil, node: nil)
      new(budget:, oracle:, node:).call
    end

    def initialize(budget:, oracle: nil, node: nil)
      @budget = budget
      @oracle = oracle || Config.oracle_client
      @node = node || NodeClient.default
      @global_client = L1::Bitcoind::Client.new
    end

    def call
      return budget.dlc_contract if budget.dlc_contract.present?
      raise Error, I18n.t("services.dlc.contract_setup.missing_peg") unless budget.peg_set?

      announcement = oracle.announce_numeric(event_id: event_id, maturity_epoch: maturity_epoch)
      num_digits = announcement.num_digits || Config.num_digits

      peg_wallet = L1::UserWallet.for(budget.borrower)
      investor_wallet = L1::UserWallet.for(budget.investor)
      peg_sats = budget.borrower_locked_sats
      investor_sats = budget.investor_locked_sats
      validate_on_chain_balances!(peg_wallet, investor_wallet, peg_sats, investor_sats)

      peg_inputs = coins_to_inputs(peg_wallet.select_coins(peg_sats + FUNDING_FEE_BUFFER_SATS))
      investor_inputs = coins_to_inputs(investor_wallet.select_coins(investor_sats + FUNDING_FEE_BUFFER_SATS))
      peg_change_address = peg_wallet.change_address
      investor_change_address = investor_wallet.change_address
      investor_payout_address = investor_wallet.receive_address(label: "dlc_settlement")

      points = PayoutCurve.for(budget: budget, num_digits: num_digits)
      contract = node.create_contract(
        oracle_announcement: announcement.hex,
        payouts: points.map { |p| { outcome: p.outcome, peg_sats: p.peg_sats, investor_sats: p.investor_sats } },
        peg_collateral_sats: peg_sats,
        investor_collateral_sats: investor_sats,
        refund_locktime: budget.refund_locktime_height,
        peg_inputs: peg_inputs,
        investor_inputs: investor_inputs,
        peg_change_address: peg_change_address,
        investor_change_address: investor_change_address,
        investor_payout_address: investor_payout_address,
        contract_id: event_id
      )

      broadcast_funding!(contract, peg_wallet, investor_wallet)
      record_collateral_lock!(contract, peg_wallet, investor_wallet, investor_payout_address)

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
        status: :funded
      )
    rescue OracleClient::Error, NodeClient::Error => e
      raise Error, I18n.t("services.dlc.contract_setup.setup_failed", message: e.message)
    rescue L1::Bitcoind::Error => e
      raise Error, I18n.t("services.dlc.contract_setup.funding_failed", message: e.message)
    end

    private

    attr_reader :budget, :oracle, :node

    # Sign the unsigned 2-of-2 funding tx returned by the sidecar with both
    # reserve wallets (peg + investor P2WPKH inputs) and broadcast it. The segwit
    # txid is stable pre-witness, so it must match the funding_txid the sidecar
    # bound the CETs to — otherwise the CETs would be invalid (STOP condition).
    def broadcast_funding!(contract, peg_wallet, investor_wallet)
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
      txid
    end

    # The DLC funding output is the collateral lock. Record it on the budget so
    # `l1_multisig_provisioned?` is true and the recovery package documents it.
    def record_collateral_lock!(contract, peg_wallet, investor_wallet, investor_payout_address)
      package = budget.recovery_package&.deep_dup || {}
      package["escrow"] = {
        "outpoint" => "#{contract.funding_txid}:#{contract.funding_vout}",
        "peg_party_pubkey" => peg_wallet.identity_pubkey,
        "investor_pubkey" => investor_wallet.identity_pubkey,
        "amount_sats" => budget.borrower_locked_sats + budget.investor_locked_sats,
        "investor_payout_address" => investor_payout_address,
        "note" => "Fase 1 — il funding 2-of-2 del DLC È il lock del collateral"
      }

      budget.update!(
        peg_party_pubkey: peg_wallet.identity_pubkey,
        investor_pubkey: investor_wallet.identity_pubkey,
        escrow_txid: contract.funding_txid,
        escrow_vout: contract.funding_vout,
        refund_delay_blocks: Budget::REFUND_DELAY_BLOCKS,
        recovery_package: package
      )
      budget.reload
    end

    def validate_on_chain_balances!(peg_wallet, investor_wallet, peg_sats, investor_sats)
      required_peg = peg_sats + FUNDING_FEE_BUFFER_SATS
      if peg_wallet.spendable_sats < required_peg
        raise Error,
              I18n.t("services.dlc.contract_setup.insufficient_on_chain_balance",
                wallet_name: peg_wallet.wallet_name,
                available_sats: peg_wallet.spendable_sats,
                required_sats: required_peg)
      end

      required_investor = investor_sats + FUNDING_FEE_BUFFER_SATS
      return if investor_wallet.spendable_sats >= required_investor

      raise Error,
            I18n.t("services.dlc.contract_setup.insufficient_on_chain_balance",
              wallet_name: investor_wallet.wallet_name,
              available_sats: investor_wallet.spendable_sats,
              required_sats: required_investor)
    end

    def coins_to_inputs(coins)
      coins.map do |coin|
        {
          txid: coin.fetch("txid"),
          vout: coin.fetch("vout"),
          amount_sats: (coin.fetch("amount").to_d * 100_000_000).to_i
        }
      end
    end

    def event_id
      "deal-#{budget.id}"
    end

    # Maturity timestamp the oracle commits to. For Pythia (price-feed oracle)
    # this is a near-future scheduled slot (see Config.oracle_maturity_epoch);
    # otherwise the budget calendar maturity (period_end) is used. Memoized so the
    # same epoch is announced, persisted and later attested.
    def maturity_epoch
      @maturity_epoch ||= Config.oracle_maturity_epoch || budget.period_end.to_time.to_i
    end
  end
end
