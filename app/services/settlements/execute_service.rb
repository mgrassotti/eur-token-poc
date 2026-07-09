# frozen_string_literal: true

module Settlements
  class ExecuteService
    class Error < StandardError; end

    Payout = Data.define(
      :user,
      :token_cents,
      :btc_sats,
      :liability_eur_cents,
      :eur_at_settlement
    )

    def self.call(budget:, end_btc_eur_rate:, set_by: nil, force_liquidation: false)
      new(budget:, end_btc_eur_rate:, set_by:, force_liquidation:).call
    end

    def initialize(budget:, end_btc_eur_rate:, set_by: nil, force_liquidation: false)
      @budget = budget
      @end_btc_eur_rate = end_btc_eur_rate.to_d
      @set_by = set_by
      @force_liquidation = force_liquidation
    end

    def call
      validate!

      token_accounts = budget.token_accounts.lock.where("balance_cents > 0").order(:id).to_a
      payoff = Payoffs::FloorEurCalculator.call(
        notional_eur_cents: budget.notional_eur_cents,
        notional_total_cents: budget.amount_eur_cents,
        holder_shares_cents: token_accounts.map(&:balance_cents),
        spot_eur_per_btc: end_btc_eur_rate,
        rate_bps_monthly: budget.rate_bps_monthly,
        months_elapsed: budget.months_elapsed,
        escrow_total_sats: budget.pool_sats
      )

      payouts = []

      ActiveRecord::Base.transaction do
        payouts = settle!(token_accounts, payoff)

        budget.collateral_lock.lock!

        raise Error, I18n.t("services.settlements.execute.collateral_insufficient") if payoff.investor_remainder_sats.negative?

        settlement = Settlement.create!(
          budget: budget,
          end_btc_eur_rate: end_btc_eur_rate,
          total_btc_to_holders_sats: payoff.total_holder_sats,
          btc_to_investor_sats: payoff.investor_remainder_sats,
          executed_at: Time.current
        )

        budget.update!(status: :settled)

        market_rate_updated = update_market_rate!

        result = Result.new(
          settlement: settlement,
          payouts: payouts,
          payoff: payoff,
          borrower: budget.borrower,
          borrower_btc_sats: 0,
          investor: budget.investor,
          investor_btc_sats: payoff.investor_remainder_sats,
          investor_eur_at_end: BtcConversion.sats_to_eur(payoff.investor_remainder_sats, end_btc_eur_rate),
          peg_eur_per_btc: budget.peg_eur_per_btc,
          end_btc_eur_rate: end_btc_eur_rate,
          market_rate_updated: market_rate_updated
        )

        result
      end
    end

    Result = Data.define(
      :settlement,
      :payouts,
      :payoff,
      :borrower,
      :borrower_btc_sats,
      :investor,
      :investor_btc_sats,
      :investor_eur_at_end,
      :peg_eur_per_btc,
      :end_btc_eur_rate,
      :market_rate_updated
    )

    private

    attr_reader :budget, :end_btc_eur_rate, :set_by, :force_liquidation

    def validate!
      raise Error, I18n.t("services.settlements.execute.budget_not_active") unless budget.active?
      raise Error, I18n.t("services.settlements.execute.invalid_end_rate") unless end_btc_eur_rate.positive?
      raise Error, I18n.t("services.settlements.execute.missing_peg") unless budget.peg_set?
      raise Error, I18n.t("services.settlements.execute.already_settled") if budget.settlement.present?
      return if force_liquidation || budget.ready_for_settlement?

      raise Error, I18n.t("services.settlements.execute.available_from_block", maturity_block_height: budget.maturity_block_height)
    end

    def update_market_rate!
      return false unless set_by

      market_rate = MarketRate.current
      return false if market_rate.btc_eur_per_btc.to_d == end_btc_eur_rate

      market_rate.update!(btc_eur_per_btc: end_btc_eur_rate, set_by: set_by)
      true
    end

    def settle!(token_accounts, payoff)
      raise Error, I18n.t("services.settlements.execute.dlc_not_funded") unless budget.dlc_contract&.funded?

      # Snapshot holder allocations before redemption zeroes the token balances;
      # the DLC peg_pot distribution fans out on these maturity shares.
      dlc_shares = token_accounts.map { |ta| { user: ta.user, cents: ta.balance_cents } }

      holder_payouts = []
      payouts = token_accounts.each_with_index.map do |token_account, index|
        allocation = payoff.holder_allocations[index]
        holder = token_account.user
        holder_payouts << { user: holder, btc_sats: allocation.btc_sats }
        payout_for(token_account, allocation, payoff).tap do
          redeem_rgb!(holder)
          Rgb::ProjectionService.apply_redeem!(budget: budget, holder: holder)
        end
      end

      settlement_txid = settle_via_dlc!(dlc_shares)
      persist_settlement_txid!(settlement_txid)

      users_to_sync = holder_payouts.map { |p| p[:user] }.uniq
      users_to_sync << budget.investor
      users_to_sync.uniq.each { |user| L1::SyncReserveBalanceService.call(user: user) }

      payouts
    end

    # Settlement path: the oracle attestation executes the CET that pays
    # peg_pot + investor; peg_pot is then distributed pro-rata to the holders.
    def settle_via_dlc!(shares)
      result = Dlc::SettlementService.call(budget: budget, end_btc_eur_rate: end_btc_eur_rate)
      Dlc::Distribution.call(budget: budget, peg_pot_sats: result.peg_pot_sats, shares: shares)
      persist_dlc_recovery!
      result.cet_txid
    end

    def persist_dlc_recovery!
      package = budget.reload.recovery_package&.deep_dup || {}
      package["dlc"] = Dlc::RecoveryPackage.build(budget: budget)
      budget.update!(recovery_package: package)
    end

    # Best-effort RGB redemption. Settlement finality lives on L1 (the BTC payout
    # below is what matters); the RGB EURT redemption is an on-chain mirror that
    # can lag confirmations. A redemption failure must not block settlement — log
    # it and let the DB projection reconcile.
    def redeem_rgb!(holder)
      Rgb::RedeemService.call(budget: budget, holder: holder)
    rescue Rgb::RedeemService::Error, Rgb::LightningClient::Error, Rgb::Nodes::Error => e
      Rails.logger.warn("Redemption RGB best-effort fallita per #{holder.name}: #{e.message}")
    end

    def persist_settlement_txid!(txid)
      package = budget.recovery_package.deep_dup
      package["settlement_txid"] = txid
      package["psbt_maturity"] = package.fetch("psbt_maturity", {}).merge("broadcast_txid" => txid)
      budget.update!(recovery_package: package)
    end

    def payout_for(token_account, allocation, payoff)
      token_cents = token_account.balance_cents
      Payout.new(
        user: token_account.user,
        token_cents: token_cents,
        btc_sats: allocation.btc_sats,
        liability_eur_cents: payoff.liability_eur_cents,
        eur_at_settlement: (payoff.liability_eur_cents * token_cents / budget.amount_eur_cents) / 100.0
      )
    end
  end
end
