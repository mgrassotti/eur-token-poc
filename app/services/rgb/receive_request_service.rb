# frozen_string_literal: true

module Rgb
  # Mints a short-lived RGB receive invoice on the current user's RLN and persists
  # a ReceiveRequest so another user can pay via QR (mat:pay/1?...).
  class ReceiveRequestService
    class Error < StandardError; end

    def self.call(user:, amount_cents: nil)
      new(user:, amount_cents:).call
    end

    def initialize(user:, amount_cents: nil)
      @user = user
      @amount_cents = amount_cents.present? ? amount_cents.to_i : nil
    end

    def call
      if amount_cents && !amount_cents.positive?
        raise Error, I18n.t("services.rgb.receive_request.invalid_amount")
      end

      node = WalletSetupService.ensure_for!(user)
      invoice = node.rgb_invoice(amount: amount_cents)
      recipient_id = invoice.fetch("recipient_id")

      ReceiveRequest.create!(
        user: user,
        amount_eur_cents: amount_cents,
        recipient_id: recipient_id,
        invoice: invoice["invoice"],
        expires_at: ReceiveRequest::TTL.from_now
      )
    rescue WalletSetupService::Error, LightningClient::Error, Nodes::Error => e
      raise Error, e.message
    end

    private

    attr_reader :user, :amount_cents
  end
end
