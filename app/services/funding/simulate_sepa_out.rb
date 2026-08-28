# frozen_string_literal: true

module Funding
  # After CET, if the saver chose EUR, debit the bank BTC-equivalent and
  # simulate an outgoing SEPA to their IBAN.
  class SimulateSepaOut
    class Error < StandardError; end

    def self.call(budget:)
      new(budget:).call
    end

    def initialize(budget:)
      @budget = budget
    end

    def call
      return unless @budget.saver_eur?
      raise Error, "missing saver IBAN" if @budget.saver_payout_iban.blank?

      liability = @budget.liability_eur_cents(at_height: @budget.maturity_block_height)
      bank = BankAccount.default

      ActiveRecord::Base.transaction do
        bank.lock!
        bank.debit!(liability)
        BankTransfer.create!(
          bank_account: bank,
          budget: @budget,
          funding_request: @budget.saver_funding_request,
          direction: :outbound,
          amount_eur_cents: liability,
          counterparty_iban: @budget.saver_payout_iban,
          status: :completed
        )
      end
    rescue ArgumentError => e
      raise Error, e.message
    end
  end
end
