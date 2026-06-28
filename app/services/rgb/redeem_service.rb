# frozen_string_literal: true

module Rgb
  # Redemption (ritiro) RGB20 EURT a settlement: drena il saldo settled del holder
  # verso il nodo issuer/treasury. RGB non espone un burn nativo, quindi la
  # redemption all'issuer ritira di fatto i token dalla circolazione degli holder
  # in cambio del payout BTC dell'escrow. Operazione solo on-chain via RLN:
  # nessuna scrittura DB qui — la proiezione la aggiorna ProjectionService.apply_redeem!.
  class RedeemService
    class Error < StandardError; end

    Result = Data.define(:asset_id, :amount_cents, :txid, :recipient_id, :status)

    def self.call(budget:, holder:)
      new(budget:, holder:).call
    end

    def initialize(budget:, holder:)
      @budget = budget
      @holder = holder
    end

    def call
      return skipped unless redeemable?

      amount_cents = BalanceService.settled(user: holder, budget: budget)
      return empty(amount_cents) if amount_cents <= 0

      issuer = ensure_issuer_node!
      holder_node = WalletSetupService.ensure_for!(holder)

      invoice = issuer.rgb_invoice(asset_id: asset_id, amount: amount_cents)
      recipient_id = invoice.fetch("recipient_id")

      transfer = holder_node.send_asset(
        asset_id: asset_id,
        amount: amount_cents,
        recipient_id: recipient_id,
        transport_endpoints: [Config.rln_unlock_params[:proxy_endpoint]]
      )

      Result.new(
        asset_id: asset_id,
        amount_cents: amount_cents,
        txid: transfer.fetch("txid"),
        recipient_id: recipient_id,
        status: :redeemed
      )
    end

    private

    attr_reader :budget, :holder

    def redeemable?
      asset_id.present? && Nodes.available_for?(holder)
    end

    def asset_id
      budget.rgb_asset_id
    end

    def ensure_issuer_node!
      issuer = Nodes.issuer
      begin
        issuer.init(password: Config.rln_password)
      rescue LightningClient::Error
        nil
      end
      begin
        issuer.unlock(password: Config.rln_password, **Config.rln_unlock_params)
      rescue LightningClient::Error
        nil
      end
      begin
        issuer.create_utxos(num: 4, size: 32_500, fee_rate: 5)
      rescue LightningClient::Error
        nil
      end
      issuer
    end

    def skipped
      Result.new(asset_id: asset_id, amount_cents: 0, txid: nil, recipient_id: nil, status: :skipped)
    end

    def empty(amount_cents)
      Result.new(asset_id: asset_id, amount_cents: amount_cents, txid: nil, recipient_id: nil, status: :empty)
    end
  end
end
