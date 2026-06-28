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
      ensure_rgb_ready!

      settled = Rgb::BalanceService.settled(user: from_user, budget: budget)
      raise Error, "Insufficient token balance" if settled < amount_cents

      rgb_result = Rgb::TransferService.call(
        budget: budget,
        from_user: from_user,
        to_user: to_user,
        amount_cents: amount_cents
      )

      Rgb::ProjectionService.apply_transfer!(
        budget: budget,
        from_user: from_user,
        to_user: to_user,
        amount_cents: amount_cents,
        rgb_result: rgb_result
      )
    rescue Rgb::TransferService::Error, Rgb::LibTransferService::Error,
           Rgb::LightningClient::Error, Rgb::Nodes::Error, Rgb::ProjectionService::Error => e
      raise Error, e.message
    end

    private

    attr_reader :budget, :from_user, :to_user, :amount_cents

    def validate!
      raise Error, "Budget is not active" unless budget.active?
      raise Error, "Amount must be positive" unless amount_cents.positive?
      raise Error, "Cannot transfer to yourself" if from_user.id == to_user.id
    end

    def ensure_rgb_ready!
      raise Error, "Escrow not provisioned" unless budget.l1_multisig_provisioned?
      raise Error, "RGB asset missing on deal" if budget.rgb_asset_id.blank?
      raise Error, "RGB genesis missing" unless budget.rgb_assignments.exists?

      Rgb::Config.ensure_node!(from_user)
    end
  end
end
