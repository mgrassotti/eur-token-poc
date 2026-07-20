# frozen_string_literal: true

module Rgb
  # Settled RGB balance per user/deal. Primary source: the user's RLN node;
  # fallback: the DB projection (rgb_assignments) when the node is unreachable.
  # When the node is up but no longer knows the contract, returns 0 (projection may be stale).
  class BalanceService
    def self.settled(user:, budget:)
      new(user:, budget:).settled
    end

    def initialize(user:, budget:)
      @user = user
      @budget = budget
    end

    def settled
      return projection_balance unless node_balanceable?

      read_from_node
    rescue LightningClient::Error, Nodes::Error
      projection_balance
    end

    private

    attr_reader :user, :budget

    def node_balanceable?
      budget.rgb_asset_id.present? && Nodes.available_for?(user)
    end

    def read_from_node
      balance = Nodes.for_user(user).asset_balance(asset_id: budget.rgb_asset_id)
      balance["settled"].to_i
    rescue LightningClient::Error => e
      # DB projection can outlive the node's contract store (e.g. after regtest reset).
      return 0 if e.message.include?("Unknown RGB contract ID")

      raise
    end

    def projection_balance
      user.rgb_assignments.find_by(budget: budget)&.notional_share_cents.to_i
    end
  end
end
