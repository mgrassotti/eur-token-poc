# frozen_string_literal: true

module Budgets
  class CreateService
    class Error < StandardError; end

    def self.call(amount_eur_cents:, period_start:, period_end:, borrower: nil,
                  funding_address: nil, commitment_psbt: nil, borrower_name: nil,
                  skip_fund_check: false)
      new(
        borrower: borrower,
        funding_address: funding_address,
        commitment_psbt: commitment_psbt,
        borrower_name: borrower_name,
        amount_eur_cents: amount_eur_cents,
        period_start: period_start,
        period_end: period_end,
        skip_fund_check: skip_fund_check
      ).call
    end

    def initialize(borrower:, funding_address:, commitment_psbt:, borrower_name:,
                   amount_eur_cents:, period_start:, period_end:, skip_fund_check: false)
      @borrower = borrower
      @funding_address = funding_address.to_s.strip.presence
      @commitment_psbt = commitment_psbt.to_s.strip.presence
      @borrower_name = borrower_name
      @amount_eur_cents = amount_eur_cents
      @period_start = period_start
      @period_end = period_end
      @skip_fund_check = skip_fund_check
    end

    def call
      validate!

      peg_eur_per_btc = MarketRate.current.btc_eur_per_btc
      locked_sats = ReserveRequirement.borrower_sats_for(amount_eur_cents, peg_eur_per_btc)
      required_sats = ReserveRequirement.borrower_required_sats_for(amount_eur_cents, peg_eur_per_btc)

      resolve_borrower!
      reserved = validate_funds!(required_sats)

      ActiveRecord::Base.transaction do
        borrower.btc_account.lock!

        Budget.create!(
          borrower: borrower,
          amount_eur_cents: amount_eur_cents,
          collateral_eur_cents: amount_eur_cents * Budget::INVESTOR_COLLATERAL_MULTIPLIER,
          period_start: period_start,
          period_end: period_end,
          borrower_locked_sats: locked_sats,
          status: :pending,
          funding_address: @funding_address || borrower.btc_account.reserve_receive_address,
          commitment_psbt: @commitment_psbt,
          reserved_outpoints: reserved
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

    def resolve_borrower!
      return if @borrower.present?

      raise Error, "funding_address required" if @funding_address.blank?
      raise Error, "commitment_psbt required for anonymous create" if @commitment_psbt.blank?

      @borrower = Users::GuestFinder.find_or_create_by_address!(
        address: @funding_address,
        name: @borrower_name
      )
    end

    def validate_funds!(required_sats)
      return nil if @skip_fund_check

      if @commitment_psbt.present?
        return validate_commitment!(required_sats)
      end

      raise Error, "commitment_psbt required for anonymous create" if @borrower.blank?

      # Legacy path (web / unit specs): DB/UserWallet spendable balance.
      available_sats = ReserveRequirement.available_sats_for(borrower)
      if available_sats < required_sats
        raise Error,
              ReserveRequirement.insufficient_message(
                label: I18n.t("services.budgets.reserve_requirement.borrower_label"),
                required_sats: required_sats,
                available_sats: available_sats,
                eur_per_btc: MarketRate.current.btc_eur_per_btc
              )
      end

      nil
    rescue L1::CommitmentPsbtValidator::Error => e
      raise Error, e.message
    end

    def validate_commitment!(required_sats)
      L1::CommitmentPsbtValidator.call(
        psbt_base64: @commitment_psbt,
        required_sats: required_sats,
        funding_address: @funding_address || borrower.btc_account.reserve_receive_address
      )
    end
  end
end
