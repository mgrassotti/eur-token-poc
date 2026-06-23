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
      locked_sats = BtcConversion.eur_cents_to_sats(amount_eur_cents, peg_eur_per_btc)

      ActiveRecord::Base.transaction do
        borrower_btc = borrower.btc_account.lock!
        available_sats = reserve_sats_for(borrower, borrower_btc)

        if available_sats < locked_sats
          raise Error, "Saldo insufficiente sul conto di riserva"
        end

        unless l1_enabled?
          borrower_btc.update!(balance_sats: borrower_btc.balance_sats - locked_sats)
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
      raise Error, "L'admin deve impostare il cambio BTC/€ corrente" unless MarketRate.current.set?
      raise Error, "Importo richiesto non valido" unless amount_eur_cents.to_i.positive?
      raise Error, "Periodo non valido" if period_start.blank? || period_end.blank? || period_end < period_start
    end

    def l1_enabled?
      L1.enabled?
    end

    def reserve_sats_for(user, btc_account)
      return btc_account.balance_sats unless l1_enabled?

      L1::UserWallet.for(user).spendable_sats
    end
  end
end
