# frozen_string_literal: true

module Funding
  class CreateRequest
    class Error < StandardError; end

    TERM_MONTHS = 1
    RATE_BPS = 100

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(role:, amount_eur_cents:, receive_address:, payout_mode:,
                   payout_iban: nil, display_name: nil, user: nil)
      @role = role.to_s
      @amount_eur_cents = amount_eur_cents.to_i
      @receive_address = receive_address.to_s.strip
      @payout_mode = payout_mode.to_s
      @payout_iban = payout_iban.to_s.strip.presence
      @display_name = display_name
      @user = user
    end

    def call
      validate!

      user = @user || Users::GuestFinder.find_or_create_by_address!(
        address: @receive_address,
        name: @display_name
      )

      FundingRequest.create!(
        user: user,
        role: @role,
        status: :awaiting_deposit,
        amount_eur_cents: @amount_eur_cents,
        remaining_eur_cents: @amount_eur_cents,
        payout_mode: @payout_mode,
        payout_iban: @payout_iban,
        receive_address: @receive_address,
        display_name: @display_name.presence || user.name
      )
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.message
    end

    private

    def validate!
      raise Error, I18n.t("services.budgets.create.market_rate_required") unless MarketRate.current.set?
      raise Error, I18n.t("services.budgets.create.invalid_amount") unless @amount_eur_cents.positive?
      raise Error, "receive_address required" if @receive_address.blank?
      raise Error, "payout_iban required" if @role == "saver" && @payout_mode == "eur" && @payout_iban.blank?
      raise Error, "investors cannot cash out in EUR" if @role == "investor" && @payout_mode == "eur"
    end
  end
end
