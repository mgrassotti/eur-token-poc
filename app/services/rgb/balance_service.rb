# frozen_string_literal: true

module Rgb
  # Saldo RGB settled per utente/deal — fonte primaria: sidecar; fallback proiezione DB.
  class BalanceService
    def self.settled(user:, budget:)
      new(user:, budget:).settled
    end

    def initialize(user:, budget:)
      @user = user
      @budget = budget
    end

    def settled
      return projection_balance unless sidecar_balanceable?

      read_from_sidecar
    rescue SidecarClient::Error
      projection_balance
    end

    private

    attr_reader :user, :budget

    def sidecar_balanceable?
      budget.rgb_asset_id.present? && user.btc_account&.rgb_wallet_id.present? &&
        SidecarClient.instance.available?
    end

    def read_from_sidecar
      wallet_id = user.btc_account.rgb_wallet_id
      assets = SidecarClient.instance.list_assets(wallet_id).fetch("nia", [])
      entry = assets.find { |asset| asset["asset_id"] == budget.rgb_asset_id }
      entry&.dig("balance", "settled").to_i
    end

    def projection_balance
      user.rgb_assignments.find_by(budget: budget)&.notional_share_cents.to_i
    end
  end
end
