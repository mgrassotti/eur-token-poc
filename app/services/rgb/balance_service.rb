# frozen_string_literal: true

module Rgb
  # Settled / spendable RGB balance per user/deal. Primary source: the user's RLN
  # node; fallback: the DB projection (rgb_assignments) when the node is unavailable.
  #
  # - settled: off-channel RGB only (needed for /sendrgb and channel opens)
  # - spendable: settled + offchain_outbound (user-facing balance including LN)
  class BalanceService
    def self.settled(user:, budget:)
      new(user:, budget:).settled
    end

    def self.spendable(user:, budget:)
      new(user:, budget:).spendable
    end

    def initialize(user:, budget:)
      @user = user
      @budget = budget
    end

    def settled
      return projection_balance unless node_balanceable?

      read_from_node["settled"].to_i
    rescue LightningClient::Error, Nodes::Error
      projection_balance
    end

    def spendable
      return projection_balance unless node_balanceable?

      balance = read_from_node
      balance["settled"].to_i + balance["offchain_outbound"].to_i
    rescue LightningClient::Error, Nodes::Error
      projection_balance
    end

    private

    attr_reader :user, :budget

    def node_balanceable?
      budget.rgb_asset_id.present? && Nodes.available_for?(user)
    end

    def read_from_node
      Nodes.for_user(user).asset_balance(asset_id: budget.rgb_asset_id)
    end

    def projection_balance
      user.rgb_assignments.find_by(budget: budget)&.notional_share_cents.to_i
    end
  end
end
