# frozen_string_literal: true

module Rgb
  # Transfer parziale RGB20 on-chain via RLN — nessuna scrittura DB.
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
      Config.ensure_node!(from_user)
      LibTransferService.call(
        budget: budget,
        from_user: from_user,
        to_user: to_user,
        amount_cents: amount_cents
      )
    end

    private

    attr_reader :budget, :from_user, :to_user, :amount_cents
  end
end
