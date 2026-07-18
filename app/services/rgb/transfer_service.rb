# frozen_string_literal: true

module Rgb
  # Transfer parziale RGB20 — L1 /sendrgb by default, or RGB-LN via hub when
  # RGB_TRANSFER_VIA_LN=1. No DB writes (ProjectionService mirrors).
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

      if Config.transfer_via_ln?
        LnTransferService.call(
          budget: budget,
          from_user: from_user,
          to_user: to_user,
          amount_cents: amount_cents
        )
      else
        LibTransferService.call(
          budget: budget,
          from_user: from_user,
          to_user: to_user,
          amount_cents: amount_cents
        )
      end
    rescue LnTransferService::Error, LibTransferService::Error => e
      raise Error, e.message
    end

    private

    attr_reader :budget, :from_user, :to_user, :amount_cents
  end
end
