# frozen_string_literal: true

module Funding
  # Admin simulates an incoming SEPA credit for a saver request, then sends the
  # EUR-equivalent BTC to the saver's on-device wallet.
  class SimulateSepaIn
    class Error < StandardError; end

    def self.call(request:, counterparty_iban: "IT60X0000000000000000000001")
      new(request:, counterparty_iban:).call
    end

    def initialize(request:, counterparty_iban:)
      @request = request
      @counterparty_iban = counterparty_iban
    end

    def call
      raise Error, "not a saver request" unless @request.saver?
      raise Error, "request is not awaiting a deposit" unless @request.awaiting_deposit?
      raise Error, I18n.t("services.budgets.create.market_rate_required") unless MarketRate.current.set?

      bank = BankAccount.default
      sats = @request.required_sats
      txid = nil

      ActiveRecord::Base.transaction do
        bank.lock!
        bank.credit!(@request.amount_eur_cents)
        txid = send_btc!(sats)
        BankTransfer.create!(
          bank_account: bank,
          funding_request: @request,
          direction: :inbound,
          amount_eur_cents: @request.amount_eur_cents,
          counterparty_iban: @counterparty_iban,
          btc_txid: txid,
          btc_sats: sats,
          status: :completed
        )
      end

      try_autofill_utxos!
      MatchingService.call
      @request.reload
    end

    private

    def send_btc!(sats)
      L1::FundReceiveAddressService.call(address: @request.receive_address, amount_sats: sats).txid
    rescue L1::FundReceiveAddressService::Error => e
      raise Error, e.message
    end

    def try_autofill_utxos!
      wallet = L1::UserWallet.for(@request.user)
      return unless wallet.respond_to?(:select_coins)

      coins = wallet.select_coins(@request.required_sats)
      return if coins.blank?

      SubmitUtxos.call(
        request: @request,
        inputs: coins.map { |c| coin_input(c) },
        change_address: wallet.change_address,
        identity_pubkey: wallet.identity_pubkey
      )
    rescue StandardError => e
      Rails.logger.info("SEPA in: mobile must submit UTXOs (#{e.message})")
    end

    def coin_input(coin)
      {
        txid: coin.fetch("txid"),
        vout: coin.fetch("vout"),
        amount_sats: (coin.fetch("amount").to_d * 100_000_000).to_i
      }
    end
  end
end
