# frozen_string_literal: true

module Rgb
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

      sender_wallet_id = WalletSetupService.ensure_for!(from_user)
      recipient_wallet_id = WalletSetupService.ensure_for!(to_user)

      receive = client.blind_receive(
        wallet_id: recipient_wallet_id,
        asset_id: asset_id,
        amount: amount_cents
      )

      transfer = client.send_asset(
        sender_wallet_id: sender_wallet_id,
        recipient_wallet_id: recipient_wallet_id,
        asset_id: asset_id,
        recipient_id: receive.fetch("recipient_id"),
        amount: amount_cents
      )

      TransferResult.new(
        txid: transfer.fetch("txid"),
        recipient_id: receive.fetch("recipient_id"),
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

    def client
      SidecarClient.instance
    end
  end
end
