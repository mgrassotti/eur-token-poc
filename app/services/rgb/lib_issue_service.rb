# frozen_string_literal: true

module Rgb
  # Issue RGB20 NIA per deal e alloca al borrower via rgb-lib (solo on-chain).
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

      ensure_issuer_wallet!

      issuer_id = Config::ISSUER_WALLET_ID
      borrower_id = WalletSetupService.ensure_for!(budget.borrower)

      ticker = "E#{budget.id}"[0, 8]
      name = "FloorEUR deal #{budget.id}"

      issued = client.issue(
        wallet_id: issuer_id,
        ticker: ticker,
        name: name,
        precision: 0,
        amounts: [budget.amount_eur_cents]
      )

      asset_id = issued.fetch("asset_id")
      receive = client.blind_receive(
        wallet_id: borrower_id,
        asset_id: asset_id,
        amount: budget.amount_eur_cents
      )

      transfer = client.send_asset(
        sender_wallet_id: issuer_id,
        recipient_wallet_id: borrower_id,
        asset_id: asset_id,
        recipient_id: receive.fetch("recipient_id"),
        amount: budget.amount_eur_cents
      )

      IssueResult.new(
        asset_id: asset_id,
        ticker: ticker,
        name: name,
        recipient_id: receive.fetch("recipient_id"),
        issue_txid: transfer.fetch("txid"),
        amount_cents: budget.amount_eur_cents
      )
    end

    private

    attr_reader :budget

    def validate!
      raise Error, "Budget non attivo" unless budget.active?
      raise Error, "Escrow non provisionato" unless budget.l1_multisig_provisioned?
    end

    def client
      SidecarClient.instance
    end

    def ensure_issuer_wallet!
      client.create_wallet(wallet_id: Config::ISSUER_WALLET_ID)
      client.setup_wallet(Config::ISSUER_WALLET_ID)
    end
  end
end
