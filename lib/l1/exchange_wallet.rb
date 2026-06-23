# frozen_string_literal: true

module L1
  # Simulated external wallet ("Wallet esterno") — funds user reserve wallets via on-chain transfer.
  # Il mining regtest (coinbase) avviene solo qui, mai sui wallet utente.
  class ExchangeWallet
    WALLET_NAME = "l1_external_wallet"
    DISPLAY_NAME = "Wallet esterno"
    INITIAL_BALANCE_SATS = 100_000_000 # 1 BTC demo float
    COINBASE_MATURITY_BLOCKS = 101

    class Error < StandardError; end

    def initialize(client: Bitcoind::Client.new)
      @global_client = client
    end

    def transfer_to!(address:, amount_sats:)
      raise Error, "Importo non valido" unless amount_sats.to_i.positive?

      ensure_funded!(minimum_sats: amount_sats)
      raise Error, "#{DISPLAY_NAME}: saldo insufficiente" if spendable_sats < amount_sats

      txid = client.call("sendtoaddress", address, btc(amount_sats))
      confirm_regtest_block!
      txid
    end

    def spendable_sats
      ensure_wallet!
      sats_to_btc_amount(client.call("getbalance", "*", 1))
    end

    private

    def client
      @client ||= begin
        ensure_wallet!
        @global_client.with_wallet(WALLET_NAME)
      end
    end

    def ensure_wallet!
      return if wallet_loaded?

      begin
        @global_client.call("createwallet", WALLET_NAME, false, false, "", false, true)
      rescue Bitcoind::Error => e
        raise unless wallet_already_exists_error?(e)

        @global_client.call("loadwallet", WALLET_NAME) unless wallet_loaded?
      end
    end

    def ensure_funded!(minimum_sats:)
      ensure_wallet!
      target = [INITIAL_BALANCE_SATS, minimum_sats].max
      return if spendable_sats >= minimum_sats

      mine_until(target)
    end

    def mine_until(target_sats)
      loop do
        address = client.call("getnewaddress", "external_fund", "bech32")
        client.call("generatetoaddress", COINBASE_MATURITY_BLOCKS, address)
        break if spendable_sats >= target_sats
      end
    end

    def confirm_regtest_block!
      address = client.call("getnewaddress", "confirm", "bech32")
      client.call("generatetoaddress", 1, address)
    end

    def wallet_loaded?
      @global_client.call("listwallets").include?(WALLET_NAME)
    rescue Bitcoind::Error
      false
    end

    def wallet_already_exists_error?(error)
      error.message.include?("Database already exists") || error.message.include?("already exists")
    end

    def btc(sats)
      format("%.8f", sats / 100_000_000.0)
    end

    def sats_to_btc_amount(btc_float)
      (btc_float.to_d * 100_000_000).to_i
    end
  end
end
