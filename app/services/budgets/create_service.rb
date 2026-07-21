# frozen_string_literal: true

module Budgets
  class CreateService
    class Error < StandardError; end

    def self.call(borrower:, amount_eur_cents:, period_start:, period_end:)
      new(
        borrower: borrower,
        amount_eur_cents: amount_eur_cents,
        period_start: period_start,
        period_end: period_end
      ).call
    end

    def initialize(borrower:, amount_eur_cents:, period_start:, period_end:)
      @borrower = borrower
      @amount_eur_cents = amount_eur_cents
      @period_start = period_start
      @period_end = period_end
    end

    def call
      validate!

      peg_eur_per_btc = MarketRate.current.btc_eur_per_btc
      locked_sats = ReserveRequirement.borrower_sats_for(amount_eur_cents, peg_eur_per_btc)
      required_sats = ReserveRequirement.borrower_required_sats_for(amount_eur_cents, peg_eur_per_btc)

      ActiveRecord::Base.transaction do
        borrower.btc_account.lock!
        L1::SyncReserveBalanceService.call(user: borrower)

        available_sats = ReserveRequirement.available_sats_for(borrower)

        if available_sats < required_sats
          raise Error,
                ReserveRequirement.insufficient_message(
                  label: I18n.t("services.budgets.reserve_requirement.borrower_label"),
                  required_sats: required_sats,
                  available_sats: available_sats,
                  eur_per_btc: peg_eur_per_btc
                )
        end

        Budget.create!(
          borrower: borrower,
          amount_eur_cents: amount_eur_cents,
          collateral_eur_cents: amount_eur_cents * Budget::INVESTOR_COLLATERAL_MULTIPLIER,
          period_start: period_start,
          period_end: period_end,
          borrower_locked_sats: locked_sats,
          status: :pending
        )
      end
    end

    private

    attr_reader :borrower, :amount_eur_cents, :period_start, :period_end

    def validate!
      raise Error, I18n.t("services.budgets.create.market_rate_required") unless MarketRate.current.set?
      raise Error, I18n.t("services.budgets.create.invalid_amount") unless amount_eur_cents.to_i.positive?
      raise Error, I18n.t("services.budgets.create.invalid_period") if period_start.blank? || period_end.blank? || period_end < period_start
    end
  end
end
