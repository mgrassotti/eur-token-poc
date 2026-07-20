# frozen_string_literal: true

module Budgets
  class ActivateService
    class Error < StandardError; end

    PROVISION_ERRORS = [
      L1::ProvisionEscrowService::Error,
      Dlc::ContractSetupService::Error,
      Rgb::LightningClient::Error,
      Rgb::Nodes::Error,
      Rgb::WalletSetupService::Error,
      Rgb::LibIssueService::Error,
      Rgb::IssueService::Error
    ].freeze

    def self.call(budget:, investor:)
      new(budget:, investor:).call
    end

    def initialize(budget:, investor:)
      @budget = budget
      @investor = investor
    end

    def call
      validate!

      peg_eur_per_btc = MarketRate.current.btc_eur_per_btc
      collateral_sats = ReserveRequirement.investor_collateral_sats_for(budget, peg_eur_per_btc)

      ActiveRecord::Base.transaction do
        investor.btc_account.lock!
        budget.borrower.btc_account.lock!
        L1::SyncReserveBalanceService.call(user: investor)
        L1::SyncReserveBalanceService.call(user: budget.borrower)

        validate_investor_reserve!(collateral_sats, peg_eur_per_btc)
        validate_funding_balances!(collateral_sats)

        total_locked_sats = collateral_sats + budget.borrower_locked_sats

        genesis_height = ChainState.block_height
        maturity_height = genesis_height + budget.symbolic_months_duration * Budget::BLOCKS_PER_MONTH

        budget.update!(
          investor: investor,
          investor_locked_sats: collateral_sats,
          peg_eur_per_btc: peg_eur_per_btc,
          genesis_block_height: genesis_height,
          maturity_block_height: maturity_height,
          status: :active
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

    attr_reader :budget, :investor

    def validate!
      raise Error, I18n.t("services.budgets.activate.not_pending") unless budget.pending?
      raise Error, I18n.t("services.budgets.activate.investor_is_borrower") if investor.id == budget.borrower_id
      raise Error, I18n.t("services.budgets.create.market_rate_required") unless MarketRate.current.set?

      return if L1::Bitcoind::Client.new.available?

      raise Error, I18n.t("services.shared.bitcoind_unreachable")
    end

    def validate_investor_reserve!(collateral_sats, peg_eur_per_btc)
      required_sats = ReserveRequirement.investor_required_sats_for(budget, peg_eur_per_btc)
      available_sats = ReserveRequirement.available_sats_for(investor)

      return if available_sats >= required_sats

      raise Error,
            ReserveRequirement.insufficient_message(
              label: I18n.t("services.budgets.reserve_requirement.investor_label"),
              required_sats: required_sats,
              available_sats: available_sats,
              eur_per_btc: peg_eur_per_btc
            )
    end

    def validate_funding_balances!(collateral_sats)
      peg_wallet = L1::UserWallet.for(budget.borrower)
      investor_wallet = L1::UserWallet.for(investor)

      required_borrower = ReserveRequirement.borrower_funding_required_sats_for(budget)
      if peg_wallet.spendable_sats < required_borrower
        raise Error, insufficient_on_chain_message(peg_wallet, required_borrower)
      end

      required_investor = collateral_sats + ReserveRequirement.funding_fee_buffer_sats
      return if investor_wallet.spendable_sats >= required_investor

      raise Error, insufficient_on_chain_message(investor_wallet, required_investor)
    end

    def insufficient_on_chain_message(wallet, required_sats)
      I18n.t("services.dlc.contract_setup.insufficient_on_chain_balance",
        wallet_name: wallet.wallet_name,
        available_sats: wallet.spendable_sats,
        required_sats: required_sats)
    end

    def provision!(budget)
      L1::ProvisionEscrowService.call(budget: budget)
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
          status: :pending
        )
      end
    end
  end
end
