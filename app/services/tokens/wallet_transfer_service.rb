# frozen_string_literal: true

module Tokens
  # Spends EURT across one or more active deal token accounts (UTXO-style coin selection).
  class WalletTransferService
    class Error < StandardError; end

    TransferPart = Data.define(:budget, :amount_cents)

    def self.call(from_user:, to_user:, amount_cents:, preferred_budget: nil)
      new(from_user:, to_user:, amount_cents:, preferred_budget:).call
    end

    def initialize(from_user:, to_user:, amount_cents:, preferred_budget: nil)
      @from_user = from_user
      @to_user = to_user
      @amount_cents = amount_cents.to_i
      @preferred_budget = preferred_budget
    end

    def call
      validate!

      parts = nil
      ActiveRecord::Base.transaction do
        accounts = spendable_accounts
        parts = plan_transfers(accounts)
        parts.each do |part|
          TransferService.call(
            budget: part.budget,
            from_user: from_user,
            to_user: to_user,
            amount_cents: part.amount_cents
          )
        end
      end

      parts
    end

    private

    attr_reader :from_user, :to_user, :amount_cents, :preferred_budget

    def validate!
      raise Error, "Amount must be positive" unless amount_cents.positive?
      raise Error, "Cannot transfer to yourself" if from_user.id == to_user.id
    end

    def spendable_accounts
      accounts = from_user.token_accounts
                          .joins(:budget)
                          .merge(Budget.active)
                          .where("token_accounts.balance_cents > 0")
                          .includes(:budget)
                          .lock
                          .to_a

      order_accounts(accounts)
    end

    def order_accounts(accounts)
      return accounts if preferred_budget.blank?

      preferred, others = accounts.partition { |account| account.budget_id == preferred_budget.id }
      preferred.sort_by { |account| -account.updated_at.to_i } +
        others.sort_by { |account| -account.updated_at.to_i }
    end

    def plan_transfers(accounts)
      total = accounts.sum(&:balance_cents)
      raise Error, "Insufficient token balance" if total < amount_cents

      single = accounts.find { |account| account.balance_cents >= amount_cents }
      return [TransferPart.new(budget: single.budget, amount_cents: amount_cents)] if single

      remaining = amount_cents
      parts = []

      accounts.sort_by(&:balance_cents).each do |account|
        break if remaining.zero?

        take = [account.balance_cents, remaining].min
        next if take.zero?

        parts << TransferPart.new(budget: account.budget, amount_cents: take)
        remaining -= take
      end

      raise Error, "Insufficient token balance" if remaining.positive?

      parts
    end
  end
end
