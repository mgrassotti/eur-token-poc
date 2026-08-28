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

      token_accounts = saver_token_accounts
      payoff = Payoffs::FloorEurCalculator.call(
        notional_eur_cents: budget.notional_eur_cents,
        notional_total_cents: budget.amount_eur_cents,
        holder_shares_cents: token_accounts.map { |ta| ta[:cents] },
        spot_eur_per_btc: end_btc_eur_rate,
        rate_bps_monthly: budget.rate_bps_monthly,
        months_elapsed: settlement_months_elapsed,
        escrow_total_sats: budget.pool_sats
      )

      result = nil

      ActiveRecord::Base.transaction do
        payouts = settle!(token_accounts, payoff)

        budget.collateral_lock.lock!

        raise Error, I18n.t("services.settlements.execute.collateral_insufficient") if payoff.investor_remainder_sats.negative?

        holder_total = payouts.sum(&:btc_sats)
        investor_sats = actual_investor_payout_sats

        settlement = Settlement.create!(
          budget: budget,
          end_btc_eur_rate: end_btc_eur_rate,
          total_btc_to_holders_sats: holder_total,
          btc_to_investor_sats: investor_sats,
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
          investor_btc_sats: investor_sats,
          investor_eur_at_end: BtcConversion.sats_to_eur(investor_sats, end_btc_eur_rate),
          peg_eur_per_btc: budget.peg_eur_per_btc,
          end_btc_eur_rate: end_btc_eur_rate,
          market_rate_updated: market_rate_updated
        )
      end

      post_settlement!(result)
      result
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
      raise Error, I18n.t("services.settlements.execute.dlc_not_funded") unless budget.dlc_contract&.funded?
      return if force_liquidation || budget.ready_for_settlement?

      raise Error, I18n.t("services.settlements.execute.available_from_block", maturity_block_height: budget.maturity_block_height)
    end

    def settlement_months_elapsed
      height = force_liquidation ? ChainState.block_height : budget.maturity_block_height
      budget.months_elapsed(at_height: height)
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

      dlc_shares = token_accounts.map { |ta| { user: ta[:user], cents: ta[:cents] } }

      cet_result = Dlc::SettlementService.call(budget: budget, end_btc_eur_rate: end_btc_eur_rate)
      holder_targets = holder_targets_for(payoff, cet_result, token_accounts)
      distributions = Dlc::Distribution.call(
        budget: budget,
        peg_pot_sats: cet_result.peg_pot_sats,
        shares: dlc_shares,
        holder_targets: holder_targets,
        address_resolver: saver_address_resolver
      )
      distribution_by_user = distributions.index_by(&:user)

      persist_settlement_txid!(cet_result.cet_txid)
      persist_dlc_recovery!

      payouts = token_accounts.map do |token_account|
        actual_sats = distribution_by_user.fetch(token_account[:user]).sats
        payout_for_holder(token_account, actual_sats, payoff)
      end

      close_holder_shares!(token_accounts)

      payouts
    end

    def saver_token_accounts
      accounts = budget.token_accounts.lock.where("balance_cents > 0").order(:id).to_a
      if accounts.any?
        return accounts.map { |ta| { user: ta.user, cents: ta.balance_cents, record: ta } }
      end

      Budgets::AssignSaverShareService.call(budget: budget)
      [{ user: budget.borrower, cents: budget.amount_eur_cents, record: budget.token_accounts.find_by!(user: budget.borrower) }]
    end

    def saver_address_resolver
      lambda do |user|
        if user.id == budget.borrower_id
          budget.saver_payout_address.presence || budget.funding_address.presence ||
            L1::UserWallet.for(user).receive_address(label: "dlc_payout")
        else
          budget.investor_payout_address.presence ||
            L1::UserWallet.for(user).receive_address(label: "dlc_payout")
        end
      end
    end

    def holder_targets_for(payoff, cet_result, token_accounts)
      requested = payoff.holder_allocations.map(&:btc_sats)
      total_requested = requested.sum
      cet_total = cet_result.peg_pot_sats.to_i + cet_result.investor_sats.to_i
      fee_buffer = Dlc::Distribution.fee_estimate(token_accounts.size)

      scaled = if cet_total < total_requested + fee_buffer && total_requested.positive?
                 scale_sats_proportionally(requested, [cet_total - fee_buffer, 0].max)
               else
                 requested
               end

      token_accounts.zip(scaled).map do |token_account, sats|
        { user: token_account[:user], sats: sats }
      end
    end

    def scale_sats_proportionally(amounts, target_total)
      total = amounts.sum
      return amounts if total <= target_total

      scaled = []
      assigned = 0
      amounts[0..-2].each do |amount|
        sats = (target_total * amount) / total
        scaled << sats
        assigned += sats
      end
      scaled << target_total - assigned
    end

    def actual_investor_payout_sats
      budget.reload.recovery_package&.dig("dlc_distribution", "investor_payout_sats").to_i
    end

    def persist_dlc_recovery!
      package = budget.reload.recovery_package&.deep_dup || {}
      package["dlc"] = Dlc::RecoveryPackage.build(budget: budget)
      budget.update!(recovery_package: package)
    end

    def persist_settlement_txid!(txid)
      package = budget.recovery_package&.deep_dup || {}
      package["settlement_txid"] = txid
      package["psbt_maturity"] = package.fetch("psbt_maturity", {}).merge("broadcast_txid" => txid)
      budget.update!(recovery_package: package)
    end

    def post_settlement!(result)
      Funding::SimulateSepaOut.call(budget: budget.reload) if budget.saver_eur?
      Funding::QueueReinvest.call(budget: budget)
    rescue Funding::SimulateSepaOut::Error, Funding::CreateRequest::Error => e
      Rails.logger.warn("Post-settlement payout failed for budget ##{budget.id}: #{e.message}")
      result
    end

    def close_holder_shares!(token_accounts)
      token_accounts.each do |token_account|
        record = token_account[:record]
        next unless record

        record.update!(balance_cents: 0)
      end
    end

    def payout_for_holder(token_account, btc_sats, payoff)
      token_cents = token_account[:cents]
      Payout.new(
        user: token_account[:user],
        token_cents: token_cents,
        btc_sats: btc_sats,
        liability_eur_cents: payoff.liability_eur_cents,
        eur_at_settlement: (payoff.liability_eur_cents * token_cents / budget.amount_eur_cents) / 100.0
      )
    end
  end
end
