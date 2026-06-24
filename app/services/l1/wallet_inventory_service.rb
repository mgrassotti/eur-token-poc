# frozen_string_literal: true

module L1
  # Riepilogo wallet regtest caricati su bitcoind (saldo spendibile + equivalente €).
  class WalletInventoryService
    Row = Data.define(:wallet_name, :label, :sats, :eur)

    Result = Data.define(:available, :rows, :total_sats, :total_eur, :error_message) do
      def self.unavailable(message)
        new(available: false, rows: [], total_sats: 0, total_eur: nil, error_message: message)
      end

      def self.from_rows(rows, market_rate:)
        total_sats = rows.sum(&:sats)
        total_eur = WalletInventoryService.eur_for(total_sats, market_rate)
        new(available: true, rows: rows, total_sats: total_sats, total_eur: total_eur, error_message: nil)
      end
    end

    def self.call(market_rate: MarketRate.current)
      new(market_rate:).call
    end

    def initialize(market_rate:)
      @market_rate = market_rate
      @client = Bitcoind::Client.new
      @accounts_by_wallet = BtcAccount.includes(:user).where.not(bitcoind_wallet_name: nil).index_by(&:bitcoind_wallet_name)
    end

    def call
      return Result.unavailable("bitcoind regtest non raggiungibile. Avvia: ./bin/regtest up") unless @client.available?

      rows = discover_wallet_names.filter_map { |name| row_for(name) }.sort_by { |row| [sort_key(row), row.label] }
      Result.from_rows(rows, market_rate: @market_rate)
    rescue Bitcoind::Error => e
      Result.unavailable(e.message)
    end

    private

    attr_reader :market_rate

    def discover_wallet_names
      names = @client.call("listwallets").dup
      ensure_wallet_loaded!(ExchangeWallet::WALLET_NAME, names)
      @accounts_by_wallet.each_key { |name| ensure_wallet_loaded!(name, names) }
      names.uniq
    end

    def ensure_wallet_loaded!(wallet_name, names)
      return if names.include?(wallet_name)

      @client.call("loadwallet", wallet_name)
      names << wallet_name
    rescue Bitcoind::Error
      names
    end

    def row_for(wallet_name)
      sats = spendable_sats_for(wallet_name)
      Row.new(
        wallet_name: wallet_name,
        label: label_for(wallet_name),
        sats: sats,
        eur: self.class.eur_for(sats, market_rate)
      )
    end

    def label_for(wallet_name)
      return ExchangeWallet::DISPLAY_NAME if wallet_name == ExchangeWallet::WALLET_NAME
      return "Regtest condiviso" if wallet_name == SHARED_REGTEST_WALLET

      account = @accounts_by_wallet[wallet_name]
      return account.user.name if account

      wallet_name
    end

    def sort_key(row)
      return 0 if row.wallet_name == ExchangeWallet::WALLET_NAME
      return 1 if @accounts_by_wallet.key?(row.wallet_name)

      2
    end

    def spendable_sats_for(wallet_name)
      wallet_client = @client.with_wallet(wallet_name)
      if wallet_name == ExchangeWallet::WALLET_NAME
        btc_amount = wallet_client.call("getbalance", "*", 1)
        (btc_amount.to_d * 100_000_000).to_i
      else
        wallet_client.call("listunspent", 1, 9_999_999)
               .reject { |utxo| utxo["coinbase"] }
               .sum { |utxo| (utxo.fetch("amount").to_d * 100_000_000).to_i }
      end
    end

    class << self
      def eur_for(sats, market_rate)
        return unless market_rate&.set? && sats.positive?

        BtcConversion.sats_to_eur(sats, market_rate.btc_eur_per_btc)
      end
    end
  end
end
