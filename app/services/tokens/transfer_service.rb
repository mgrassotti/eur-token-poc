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
      raise Error, I18n.t("services.tokens.transfer.insufficient_balance") if settled < amount_cents

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
      raise Error, I18n.t("services.tokens.transfer.budget_not_active") unless budget.active?
      raise Error, I18n.t("services.tokens.transfer.invalid_amount") unless amount_cents.positive?
      raise Error, I18n.t("services.tokens.transfer.cannot_transfer_to_self") if from_user.id == to_user.id
    end

    def ensure_rgb_ready!
      raise Error, I18n.t("services.tokens.transfer.escrow_not_provisioned") unless budget.l1_multisig_provisioned?
      raise Error, I18n.t("services.tokens.transfer.rgb_asset_missing") if budget.rgb_asset_id.blank?
      raise Error, I18n.t("services.tokens.transfer.rgb_genesis_missing") unless budget.rgb_assignments.exists?

      Rgb::Config.ensure_node!(from_user)
    end
  end
end
