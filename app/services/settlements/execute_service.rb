# frozen_string_literal: true

module Settlements
  class ExecuteService
    class Error < StandardError; end

    Payout = Data.define(
      :user,
      :token_cents,
      :btc_sats,
      :peg_sats,
      :current_sats,
      :fx_to_investor_sats,
      :eur_at_peg
    )

    def self.call(budget:, end_btc_eur_rate:)
      new(budget:, end_btc_eur_rate:).call
    end

    def initialize(budget:, end_btc_eur_rate:)
      @budget = budget
      @end_btc_eur_rate = end_btc_eur_rate.to_d
      @peg_eur_per_btc = budget.peg_eur_per_btc.to_d
    end

    def call
      validate!

      payouts = []
      total_holders_sats = 0
      total_fx_to_investor_sats = 0

      ActiveRecord::Base.transaction do
        budget.token_accounts.lock.where("balance_cents > 0").find_each do |token_account|
          peg_sats, current_sats, holder_sats, fx_to_investor_sats = holder_payout(token_account.balance_cents)
          btc_account = token_account.user.btc_account.lock!

          btc_account.update!(balance_sats: btc_account.balance_sats + holder_sats)
          payouts << Payout.new(
            user: token_account.user,
            token_cents: token_account.balance_cents,
            btc_sats: holder_sats,
            peg_sats: peg_sats,
            current_sats: current_sats,
            fx_to_investor_sats: fx_to_investor_sats,
            eur_at_peg: token_account.balance_cents / 100.0
          )

          token_account.update!(balance_cents: 0)
          total_holders_sats += holder_sats
          total_fx_to_investor_sats += fx_to_investor_sats
        end

        borrower_return_sats = budget.borrower_locked_sats
        collateral = budget.collateral_lock.lock!
        investor_payout_sats = collateral.amount_sats - total_holders_sats - borrower_return_sats

        raise Error, "Collateral insufficient for token redemptions" if investor_payout_sats.negative?

        borrower_btc = budget.borrower.btc_account.lock!
        borrower_btc.update!(balance_sats: borrower_btc.balance_sats + borrower_return_sats)

        investor_btc = budget.investor.btc_account.lock!
        investor_btc.update!(balance_sats: investor_btc.balance_sats + investor_payout_sats)

        settlement = Settlement.create!(
          budget: budget,
          end_btc_eur_rate: end_btc_eur_rate,
          total_btc_to_holders_sats: total_holders_sats,
          btc_to_investor_sats: investor_payout_sats,
          executed_at: Time.current
        )

        budget.update!(status: :settled)

        Result.new(
          settlement: settlement,
          payouts: payouts,
          borrower: budget.borrower,
          borrower_btc_sats: borrower_return_sats,
          investor: budget.investor,
          investor_btc_sats: investor_payout_sats,
          total_fx_to_investor_sats: total_fx_to_investor_sats,
          investor_eur_at_end: BtcConversion.sats_to_eur(investor_payout_sats, end_btc_eur_rate),
          peg_eur_per_btc: peg_eur_per_btc,
          end_btc_eur_rate: end_btc_eur_rate
        )
      end
    end

    Result = Data.define(
      :settlement,
      :payouts,
      :borrower,
      :borrower_btc_sats,
      :investor,
      :investor_btc_sats,
      :total_fx_to_investor_sats,
      :investor_eur_at_end,
      :peg_eur_per_btc,
      :end_btc_eur_rate
    )

    private

    attr_reader :budget, :end_btc_eur_rate, :peg_eur_per_btc

    def holder_payout(token_cents)
      peg_sats = BtcConversion.token_cents_to_sats(token_cents, peg_eur_per_btc)
      current_sats = BtcConversion.token_cents_to_sats(token_cents, end_btc_eur_rate)
      fx_to_investor_sats = (peg_sats - current_sats).abs
      holder_sats = current_sats

      [peg_sats, current_sats, holder_sats, fx_to_investor_sats]
    end

    def validate!
      raise Error, "Budget is not active" unless budget.active?
      raise Error, "End BTC/EUR rate must be positive" unless end_btc_eur_rate.positive?
      raise Error, "Budget peg is missing" unless budget.peg_set?
      raise Error, "Budget already settled" if budget.settlement.present?
    end
  end
end
