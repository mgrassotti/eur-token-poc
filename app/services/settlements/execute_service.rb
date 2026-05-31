# frozen_string_literal: true

module Settlements
  class ExecuteService
    class Error < StandardError; end

    Payout = Data.define(:user, :token_cents, :btc_sats)

    def self.call(budget:, end_btc_eur_rate:)
      new(budget:, end_btc_eur_rate:).call
    end

    def initialize(budget:, end_btc_eur_rate:)
      @budget = budget
      @end_btc_eur_rate = end_btc_eur_rate.to_d
    end

    def call
      validate!

      payouts = []
      total_holders_sats = 0

      ActiveRecord::Base.transaction do
        budget.token_accounts.lock.where("balance_cents > 0").find_each do |token_account|
          sats = BtcConversion.token_cents_to_sats(token_account.balance_cents, budget.peg_eur_per_btc)
          btc_account = token_account.user.btc_account.lock!

          btc_account.update!(balance_sats: btc_account.balance_sats + sats)
          payouts << Payout.new(user: token_account.user, token_cents: token_account.balance_cents, btc_sats: sats)

          token_account.update!(balance_cents: 0)
          total_holders_sats += sats
        end

        collateral = budget.collateral_lock.lock!
        investor_btc = budget.investor.btc_account.lock!
        investor_payout_sats = collateral.amount_sats - total_holders_sats

        raise Error, "Collateral insufficient for token redemptions" if investor_payout_sats.negative?

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
          investor: budget.investor,
          investor_btc_sats: investor_payout_sats,
          end_btc_eur_rate: end_btc_eur_rate
        )
      end
    end

    Result = Data.define(:settlement, :payouts, :investor, :investor_btc_sats, :end_btc_eur_rate)

    private

    attr_reader :budget, :end_btc_eur_rate

    def validate!
      raise Error, "Budget is not active" unless budget.active?
      raise Error, "End BTC/EUR rate must be positive" unless end_btc_eur_rate.positive?
      raise Error, "Budget already settled" if budget.settlement.present?
    end
  end
end
