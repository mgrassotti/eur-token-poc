# frozen_string_literal: true

module Rgb
  # On-chain RGB20 partial transfer between two RLN nodes: the recipient node
  # issues a blinded rgb invoice, the sender node pays it via /sendasset routed
  # through the shared RGB proxy. No DB writes (ProjectionService mirrors).
  class LibTransferService
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

      asset_id = budget.rgb_asset_id
      raise Error, "rgb_asset_id mancante sul deal" if asset_id.blank?

      sender = WalletSetupService.ensure_for!(from_user)
      recipient = WalletSetupService.ensure_for!(to_user)

      invoice = recipient.rgb_invoice(asset_id: asset_id, amount: amount_cents)
      recipient_id = invoice.fetch("recipient_id")

      transfer = sender.send_asset(
        asset_id: asset_id,
        amount: amount_cents,
        recipient_id: recipient_id,
        transport_endpoints: [Config.rln_unlock_params[:proxy_endpoint]]
      )

      TransferResult.new(
        txid: transfer.fetch("txid"),
        recipient_id: recipient_id,
        asset_id: asset_id,
        amount: amount_cents
      )
    end

    private

    attr_reader :budget, :from_user, :to_user, :amount_cents

    def validate!
      raise Error, "Budget non attivo" unless budget.active?
      raise Error, "Importo non positivo" unless amount_cents.positive?

      sender_balance = BalanceService.settled(user: from_user, budget: budget)
      raise Error, "RGB balance insufficiente" if sender_balance < amount_cents
    end
  end
end
