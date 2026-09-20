# frozen_string_literal: true

module Budgets
  # Accepts a pending top-up with client-supplied funding UTXOs (BDK / on-device).
  # Does not use L1::UserWallet for balances or signing.
  #
  # When auto_sign_wallets is provided (regtest helpers only), signs + broadcasts
  # immediately. Otherwise stores an unsigned funding PSBT for the mobile sign round.
  class ActivateService
    class Error < StandardError; end

    PROVISION_ERRORS = [
      L1::ProvisionEscrowService::Error,
      Dlc::ContractSetupService::Error,
      FundingParams::Error,
      L1::UtxoSetValidator::Error
    ].freeze

    def self.call(budget:, investor:, funding:, auto_sign_wallets: nil, verify_utxos: true)
      new(
        budget: budget,
        investor: investor,
        funding: funding,
        auto_sign_wallets: auto_sign_wallets,
        verify_utxos: verify_utxos
      ).call
    end

    def initialize(budget:, investor:, funding:, auto_sign_wallets: nil, verify_utxos: true)
      @budget = budget
      @investor = investor
      @funding = funding.is_a?(FundingParams) ? funding : FundingParams.from_hash(funding)
      @auto_sign_wallets = auto_sign_wallets
      @verify_utxos = verify_utxos
    end

    def call
      validate!

      peg_eur_per_btc = MarketRate.current.btc_eur_per_btc
      collateral_sats = ReserveRequirement.investor_collateral_sats_for(budget, peg_eur_per_btc)

      validate_funding_amounts!(collateral_sats)
      verify_on_chain_utxos!(collateral_sats) if @verify_utxos

      ActiveRecord::Base.transaction do
        investor.btc_account.lock!
        budget.borrower.btc_account.lock!

        total_locked_sats = collateral_sats + budget.borrower_locked_sats

        genesis_height = ChainState.block_height
        maturity_height = genesis_height + budget.symbolic_months_duration * Budget::BLOCKS_PER_MONTH

        budget.update!(
          investor: investor,
          investor_locked_sats: collateral_sats,
          peg_eur_per_btc: peg_eur_per_btc,
          genesis_block_height: genesis_height,
          maturity_block_height: maturity_height,
          status: :active,
          borrower_change_address: funding.peg_change_address,
          investor_change_address: funding.investor_change_address,
          investor_payout_address: funding.investor_payout_address,
          investor_funding_inputs: funding.investor_inputs,
          reserved_outpoints: funding.peg_inputs,
          peg_party_pubkey: funding.peg_identity_pubkey,
          investor_pubkey: funding.investor_identity_pubkey,
          borrower_funding_signed: false,
          investor_funding_signed: false,
          borrower_dlc_signed: false,
          investor_dlc_signed: false
        )

        CollateralLock.create!(
          budget: budget,
          amount_sats: total_locked_sats,
          locked_at: Time.current
        )
      end

      provision!(budget.reload)
    end

    private

    attr_reader :budget, :investor, :funding

    def validate!
      raise Error, I18n.t("services.budgets.activate.not_pending") unless budget.pending?
      raise Error, I18n.t("services.budgets.activate.investor_is_borrower") if investor.id == budget.borrower_id
      raise Error, I18n.t("services.budgets.create.market_rate_required") unless MarketRate.current.set?

      funding.validate_presence!

      return if L1::Bitcoind::Client.new.available?

      raise Error, I18n.t("services.shared.bitcoind_unreachable")
    end

    def validate_funding_amounts!(collateral_sats)
      required_borrower = ReserveRequirement.borrower_funding_required_sats_for(budget)
      if funding.peg_total_sats < required_borrower
        raise Error,
              I18n.t("services.dlc.contract_setup.insufficient_on_chain_balance",
                wallet_name: "borrower",
                available_sats: funding.peg_total_sats,
                required_sats: required_borrower)
      end

      required_investor = collateral_sats + ReserveRequirement.funding_fee_buffer_sats
      return if funding.investor_total_sats >= required_investor

      raise Error,
            I18n.t("services.dlc.contract_setup.insufficient_on_chain_balance",
              wallet_name: "investor",
              available_sats: funding.investor_total_sats,
              required_sats: required_investor)
    end

    def verify_on_chain_utxos!(collateral_sats)
      required_borrower = ReserveRequirement.borrower_funding_required_sats_for(budget)
      required_investor = collateral_sats + ReserveRequirement.funding_fee_buffer_sats

      L1::UtxoSetValidator.call(inputs: funding.peg_inputs, required_sats: required_borrower, label: "borrower")
      L1::UtxoSetValidator.call(inputs: funding.investor_inputs, required_sats: required_investor, label: "investor")
    end

    def provision!(budget)
      L1::ProvisionEscrowService.call(budget: budget, auto_sign_wallets: @auto_sign_wallets)
      budget.reload
    rescue *PROVISION_ERRORS => e
      revert_activation!(budget)
      raise e
    end

    def revert_activation!(budget)
      ActiveRecord::Base.transaction do
        budget.lock!
        return unless budget.active?

        budget.dlc_contract&.destroy
        budget.token_accounts.destroy_all
        budget.rgb_assignments.destroy_all
        budget.collateral_lock&.destroy

        budget.update!(
          investor_id: nil,
          investor_locked_sats: 0,
          peg_eur_per_btc: nil,
          genesis_block_height: nil,
          maturity_block_height: nil,
          escrow_txid: nil,
          escrow_vout: nil,
          peg_party_pubkey: nil,
          investor_pubkey: nil,
          refund_delay_blocks: Budget::REFUND_DELAY_BLOCKS,
          recovery_package: nil,
          rgb_asset_id: nil,
          funding_psbt: nil,
          funding_tx_hex: nil,
          investor_funding_inputs: nil,
          borrower_change_address: nil,
          investor_change_address: nil,
          investor_payout_address: nil,
          borrower_funding_signed: false,
          investor_funding_signed: false,
          borrower_dlc_signed: false,
          investor_dlc_signed: false,
          status: :pending
        )
      end
    end
  end
end
