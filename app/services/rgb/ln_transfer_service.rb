# frozen_string_literal: true

module Rgb
  # User↔user EURT via RGB-LN through the MAT hub (no /sendrgb for the payment).
  # Channel opens (L1 once per edge) are handled by HubChannelService.
  class LnTransferService
    class Error < StandardError; end

    PAYMENT_TIMEOUT_SEC = 60
    INVOICE_EXPIRY_SEC = 900

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
      HubChannelService.ensure_capacity!(
        from_user: from_user,
        to_user: to_user,
        asset_id: asset_id,
        amount_cents: amount_cents,
        budget: budget
      )

      sender = Nodes.for_user(from_user)
      recipient = Nodes.for_user(to_user)

      invoice = recipient.ln_invoice(
        asset_id: asset_id,
        asset_amount: amount_cents,
        expiry_sec: INVOICE_EXPIRY_SEC
      ).fetch("invoice")

      payment = sender.send_payment(invoice: invoice)
      payment_hash = payment["payment_hash"].presence ||
                     wait_until_invoice_succeeded!(recipient, invoice)

      wait_until_payment_succeeded!(sender, payment_hash) if payment_hash.present?

      TransferResult.new(
        txid: payment_hash.presence || "ln-payment",
        recipient_id: invoice,
        asset_id: asset_id,
        amount: amount_cents
      )
    rescue HubChannelService::Error, LightningClient::Error, Nodes::Error, WalletSetupService::Error => e
      raise Error, e.message
    end

    private

    attr_reader :budget, :from_user, :to_user, :amount_cents

    def validate!
      raise Error, I18n.t("services.rgb.ln_transfer.budget_not_active") unless budget.active?
      raise Error, I18n.t("services.rgb.ln_transfer.invalid_amount") unless amount_cents.positive?
      raise Error, I18n.t("services.rgb.ln_transfer.missing_asset_id") if budget.rgb_asset_id.blank?

      spendable = BalanceService.spendable(user: from_user, budget: budget)
      raise Error, I18n.t("services.rgb.ln_transfer.insufficient_balance") if spendable < amount_cents
    end

    def wait_until_invoice_succeeded!(recipient, invoice)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PAYMENT_TIMEOUT_SEC
      loop do
        status = recipient.invoice_status(invoice: invoice).fetch("status")
        return "ln-success" if status.to_s == "Succeeded"
        raise Error, I18n.t("services.rgb.ln_transfer.payment_failed", status: status) if status.to_s == "Failed"
        raise Error, I18n.t("services.rgb.ln_transfer.payment_timeout") if timed_out?(deadline)

        sleep 1
      end
    end

    def wait_until_payment_succeeded!(sender, payment_hash)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PAYMENT_TIMEOUT_SEC
      loop do
        payment = sender.payments.find { |p| p["payment_hash"] == payment_hash }
        status = payment&.dig("status").to_s
        return if status == "Succeeded"
        raise Error, I18n.t("services.rgb.ln_transfer.payment_failed", status: status) if status == "Failed"
        raise Error, I18n.t("services.rgb.ln_transfer.payment_timeout") if timed_out?(deadline)

        sleep 1
      end
    end

    def timed_out?(deadline)
      Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end
  end
end
