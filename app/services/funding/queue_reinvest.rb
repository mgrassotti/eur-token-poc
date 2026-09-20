# frozen_string_literal: true

module Funding
  # After settlement, queue a new 1-month request when the party chose reinvest.
  # BTC stays in the app wallet; matching waits for new UTXOs.
  class QueueReinvest
    def self.call(budget:)
      new(budget:).call
    end

    def initialize(budget:)
      @budget = budget
    end

    def call
      queue_saver! if @budget.saver_reinvest?
      queue_investor! if @budget.investor_reinvest?
    end

    private

    def queue_saver!
      address = @budget.funding_address.presence || @budget.borrower.btc_account.reserve_receive_address
      return if address.blank?

      amount = @budget.liability_eur_cents(at_height: @budget.maturity_block_height)
      CreateRequest.call(
        role: :saver,
        amount_eur_cents: amount,
        receive_address: address,
        payout_mode: :reinvest,
        display_name: @budget.borrower.name,
        user: @budget.borrower
      )
    end

    def queue_investor!
      sats = @budget.settlement&.btc_to_investor_sats.to_i
      rate = @budget.settlement&.end_btc_eur_rate || MarketRate.current.btc_eur_per_btc
      amount = BtcConversion.sats_to_eur_cents(sats, rate)
      return unless amount.positive?

      address = @budget.investor_payout_address.presence ||
                @budget.investor_change_address.presence ||
                @budget.investor.btc_account.reserve_receive_address
      CreateRequest.call(
        role: :investor,
        amount_eur_cents: amount,
        receive_address: address,
        payout_mode: :reinvest,
        display_name: @budget.investor.name,
        user: @budget.investor
      )
    end
  end
end
