# frozen_string_literal: true

module Tokens
  class TransferService
    class Error < StandardError; end

    def self.call(budget:, from_user:, to_user:, amount_cents:)
      new(budget:, from_user:, to_user:, amount_cents:).call
    end

    def initialize(budget:, from_user:, to_user:, amount_cents:)
      @budget = budget
      @from_user = from_user
      @to_user = to_user
      @amount_cents = amount_cents.to_i
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        from_account = budget.token_accounts.lock.find_by!(user: from_user)
        to_account = find_or_create_to_account!

        raise Error, "Insufficient token balance" if from_account.balance_cents < amount_cents

        from_account.update!(balance_cents: from_account.balance_cents - amount_cents)
        to_account.update!(balance_cents: to_account.balance_cents + amount_cents)

        TokenTransfer.create!(
          budget: budget,
          from_user: from_user,
          to_user: to_user,
          amount_cents: amount_cents
        )
      end
    end

    private

    attr_reader :budget, :from_user, :to_user, :amount_cents

    def validate!
      raise Error, "Budget is not active" unless budget.active?
      raise Error, "Amount must be positive" unless amount_cents.positive?
      raise Error, "Cannot transfer to yourself" if from_user.id == to_user.id
    end

    def find_or_create_to_account!
      budget.token_accounts.lock.find_or_create_by!(user: to_user)
    end
  end
end
