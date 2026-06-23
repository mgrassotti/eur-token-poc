# frozen_string_literal: true

module L1
  class UserWallet
    EscrowIdentity = Data.define(:wif, :public_key_hex)
    def self.for(user)
      new(user)
    end

    def initialize(user)
      @user = user
      @btc_account = user.btc_account
      @global_client = Bitcoind::Client.new
      @wallet_name = @btc_account.bitcoind_wallet_name.presence || default_wallet_name
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

      persist_wallet_name!
    end

    def receive_address(label: "deposit")
      client.call("getnewaddress", label, "bech32")
    end

    def change_address
      client.call("getrawchangeaddress", "bech32")
    end

    def identity_pubkey
      escrow_identity_key!.public_key_hex
    end

    def escrow_identity_wif
      escrow_identity_key!.wif
    end

    # Solo UTXO da transfer (es. Wallet esterno): esclude coinbase da mining di test legacy.
    def spendable_sats
      ensure_wallet!
      transfer_unspent.sum { |utxo| (utxo.fetch("amount").to_d * 100_000_000).to_i }
    end

    def ensure_spendable!(minimum_sats)
      return if spendable_sats >= minimum_sats

      raise Bitcoind::Error,
            "Saldo spendibile insufficiente nel wallet #{wallet_name} " \
            "(#{spendable_sats} < #{minimum_sats} sats). Deposita sul conto riserva."
    end

    def select_coins(target_sats)
      unspent = transfer_unspent.sort_by { |utxo| -utxo.fetch("amount").to_d }
      selected = []
      total = 0

      unspent.each do |utxo|
        selected << utxo
        total += (utxo.fetch("amount").to_d * 100_000_000).to_i
        break if total >= target_sats
      end

      raise Bitcoind::Error, "UTXO insufficienti nel wallet #{wallet_name}" if total < target_sats

      selected
    end

    def sign_psbt!(psbt)
      result = client.call("walletprocesspsbt", psbt, true, "ALL")
      result.fetch("psbt")
    end

    def sync_balance_to_account!
      ensure_wallet!
      @btc_account.update!(balance_sats: spendable_sats)
    end

    private

    def default_wallet_name
      "user_#{@user.id}"
    end

    def escrow_identity_key!
      if @btc_account.escrow_identity_wif.present?
        return EscrowIdentity.new(
          wif: @btc_account.escrow_identity_wif,
          public_key_hex: @btc_account.escrow_identity_pubkey
        )
      end

      key = KeyMaterial.generate
      @btc_account.update!(
        escrow_identity_wif: key.wif,
        escrow_identity_pubkey: key.public_key_hex
      )
      EscrowIdentity.new(wif: key.wif, public_key_hex: key.public_key_hex)
    end

    def transfer_unspent
      client.call("listunspent", 1, 9_999_999).reject { |utxo| utxo["coinbase"] }
    end

    def persist_wallet_name!
      return if @btc_account.bitcoind_wallet_name == wallet_name

      @btc_account.update!(bitcoind_wallet_name: wallet_name)
    end

    def wallet_loaded?
      @global_client.call("listwallets").include?(wallet_name)
    rescue Bitcoind::Error
      false
    end

    def wallet_already_exists_error?(error)
      message = error.message
      message.include?("Database already exists") || message.include?("already exists")
    end
  end
end
