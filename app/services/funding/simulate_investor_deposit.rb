# frozen_string_literal: true

module Funding
  # Admin simulates an external BTC deposit into an investor request's wallet.
  class SimulateInvestorDeposit
    class Error < StandardError; end

    def self.call(request:)
      new(request:).call
    end

    def initialize(request:)
      @request = request
    end

    def call
      raise Error, "not an investor request" unless @request.investor?
      raise Error, "request is not awaiting a deposit" unless @request.awaiting_deposit?
      raise Error, I18n.t("services.budgets.create.market_rate_required") unless MarketRate.current.set?

      sats = @request.required_sats
      begin
        L1::FundReceiveAddressService.call(address: @request.receive_address, amount_sats: sats)
      rescue L1::FundReceiveAddressService::Error => e
        raise Error, e.message
      end

      try_autofill_utxos!
      MatchingService.call
      @request.reload
    end

    private

    def try_autofill_utxos!
      wallet = L1::UserWallet.for(@request.user)
      coins = wallet.select_coins(@request.required_sats)
      return if coins.blank?

      SubmitUtxos.call(
        request: @request,
        inputs: coins.map { |c| coin_input(c) },
        change_address: wallet.change_address,
        identity_pubkey: wallet.identity_pubkey
      )
    rescue StandardError => e
      Rails.logger.info("Investor deposit: mobile must submit UTXOs (#{e.message})")
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
