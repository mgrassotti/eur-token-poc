# frozen_string_literal: true

module L1
  # One bitcoind descriptor wallet per user — mirrors the Rails "conto di riserva".
  class UserWallet
    def self.for(user)
      new(user)
    end

    def initialize(user)
      @user = user
      @btc_account = user.btc_account
      @global_client = Bitcoind::Client.new
      @wallet_name = @btc_account.bitcoind_wallet_name.presence || "user_#{user.id}"
    end

    attr_reader :wallet_name

    def client
      @client ||= begin
        ensure_wallet!
        @global_client.with_wallet(wallet_name)
      end
    end

    def ensure_wallet!
      return if wallet_loaded?

      begin
        @global_client.call("createwallet", wallet_name, false, false, "", false, true)
      rescue Bitcoind::Error => e
        raise unless wallet_already_exists_error?(e)

        @global_client.call("loadwallet", wallet_name) unless wallet_loaded?
      end

      @btc_account.update!(bitcoind_wallet_name: wallet_name) if @btc_account.bitcoind_wallet_name != wallet_name
    end

    def receive_address(label: "deposit")
      client.call("getnewaddress", label, "bech32")
    end

    def spendable_sats
      ensure_wallet!
      sats_to_btc_amount(client.call("getbalance", "*", 1))
    end

    def sync_balance_to_account!
      @btc_account.update!(balance_sats: spendable_sats)
    end

    private

    def wallet_loaded?
      @global_client.call("listwallets").include?(wallet_name)
    rescue Bitcoind::Error
      false
    end

    def wallet_already_exists_error?(error)
      message = error.message
      message.include?("Database already exists") || message.include?("already exists")
    end

    def sats_to_btc_amount(btc_float)
      (btc_float.to_d * 100_000_000).to_i
    end
  end
end
