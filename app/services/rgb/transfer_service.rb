# frozen_string_literal: true

module Rgb
  # Transfer parziale RGB20 on-chain via RLN — nessuna scrittura DB.
  class TransferService
    class Error < StandardError; end

    def self.call(budget:, from_user:, to_user:, amount_cents:, rgb_recipient_id: nil)
      new(budget:, from_user:, to_user:, amount_cents:, rgb_recipient_id:).call
    end

    def initialize(budget:, from_user:, to_user:, amount_cents:, rgb_recipient_id: nil)
      @budget = budget
      @from_user = from_user
      @to_user = to_user
      @amount_cents = amount_cents.to_i
      @rgb_recipient_id = rgb_recipient_id
    end

    def call
      Config.ensure_node!(from_user)
      LibTransferService.call(
        budget: budget,
        from_user: from_user,
        to_user: to_user,
        amount_cents: amount_cents,
        rgb_recipient_id: rgb_recipient_id
      )
    end

    private

    attr_reader :budget, :from_user, :to_user, :amount_cents, :rgb_recipient_id
  end
end
