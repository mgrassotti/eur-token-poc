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

      parts = plan_transfers(spendable_positions)
      parts.each do |part|
        TransferService.call(
          budget: part.budget,
          from_user: from_user,
          to_user: to_user,
          amount_cents: part.amount_cents
        )
      end

      parts
    end

    private

    attr_reader :from_user, :to_user, :amount_cents, :preferred_budget

    def validate!
      raise Error, I18n.t("services.tokens.transfer.invalid_amount") unless amount_cents.positive?
      raise Error, I18n.t("services.tokens.transfer.cannot_transfer_to_self") if from_user.id == to_user.id
    end

    def spendable_positions
      order_positions(Spendable.positions_for(from_user))
    end

    def order_positions(positions)
      return positions if preferred_budget.blank?

      preferred, others = positions.partition { |position| position.budget.id == preferred_budget.id }
      preferred + others
    end

    def plan_transfers(positions)
      total = positions.sum(&:balance_cents)
      raise Error, I18n.t("services.tokens.transfer.insufficient_balance") if total < amount_cents

      single = positions.find { |position| position.balance_cents >= amount_cents }
      return [TransferPart.new(budget: single.budget, amount_cents: amount_cents)] if single

      remaining = amount_cents
      parts = []

      positions.sort_by(&:balance_cents).each do |position|
        break if remaining.zero?

        take = [position.balance_cents, remaining].min
        next if take.zero?

        parts << TransferPart.new(budget: position.budget, amount_cents: take)
        remaining -= take
      end

      raise Error, I18n.t("services.tokens.transfer.insufficient_balance") if remaining.positive?

      parts
    end
  end
end
