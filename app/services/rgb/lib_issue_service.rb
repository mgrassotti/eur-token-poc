# frozen_string_literal: true

module Rgb
  # Issue an RGB20 NIA asset for a deal on the borrower's own RLN node. In the
  # RLN model the borrower's node is the issuer and holds the full genesis
  # supply, so no separate issuer->borrower transfer is needed (on-chain RGB).
  class LibIssueService
    class Error < StandardError; end

    def self.call(budget:)
      new(budget:).call
    end

    def initialize(budget:)
      @budget = budget
    end

    def call
      validate!

      client = WalletSetupService.ensure_for!(budget.borrower)

      ticker = "E#{budget.id}"[0, 8]
      name = "FloorEUR deal #{budget.id}"

      issued = client.issue_asset_nia(
        ticker: ticker,
        name: name,
        precision: 0,
        amounts: [budget.amount_eur_cents]
      )

      asset = issued["asset"] || issued
      asset_id = asset.fetch("asset_id")

      IssueResult.new(
        asset_id: asset_id,
        ticker: ticker,
        name: name,
        recipient_id: nil,
        issue_txid: asset["issue_txid"],
        amount_cents: budget.amount_eur_cents
      )
    end

    private

    attr_reader :budget

    def validate!
      raise Error, I18n.t("services.rgb.lib_issue.budget_not_active") unless budget.active?
      raise Error, I18n.t("services.rgb.lib_issue.escrow_not_provisioned") unless budget.l1_multisig_provisioned?
    end
  end
end
