# frozen_string_literal: true

module Rgb
  # Ensures a user's RGB Lightning Node is ready to transact RGB: initialized,
  # unlocked, with a known pubkey and colorable UTXOs available. On regtest it
  # also funds the node from the shared miner wallet so /createutxos can run.
  # Returns the node client.
  class WalletSetupService
    class Error < StandardError; end

    # 1 BTC funded to a fresh node covers colorable UTXOs + on-chain fees.
    FUND_SATS = 100_000_000
    MIN_VANILLA_SATS = 50_000
    COLORABLE_UTXOS = 5
    COLORABLE_UTXO_SIZE = 32_500
    FEE_RATE = 5

    def self.call(user:)
      new(user:).call
    end

    # Returns the ready LightningClient for the user (raises if unavailable).
    def self.ensure_for!(user)
      call(user: user) || raise(Error, I18n.t("services.rgb.wallet_setup.node_not_configured", user_id: user.id))
    end

    def initialize(user:)
      @user = user
    end

    def call
      user.reload
      account = user.btc_account || user.create_btc_account!
      client = node_client

      init!(client)
      unlock!(client)
      persist_pubkey!(client, account)
      ensure_colorable_utxos!(client)

      client
    end

    private

    attr_reader :user

    def node_client
      Nodes.for_user(user)
    rescue Nodes::Error => e
      raise Error, e.message
    end

    def init!(client)
      client.init(password: Config.rln_password)
    rescue LightningClient::Error
      nil # node already initialized
    end

    def unlock!(client)
      client.unlock(password: Config.rln_password, **Config.rln_unlock_params)
    rescue LightningClient::Error
      nil # node already unlocked
    end

    def persist_pubkey!(client, account)
      pubkey = client.node_info["pubkey"]
      account.update!(node_pubkey: pubkey) if pubkey.present? && account.node_pubkey != pubkey
      account.reload
      user.association(:btc_account).reload
    rescue LightningClient::Error
      nil
    end

    # Tops the node up to COLORABLE_UTXOS spendable colorable UTXOs, funding the
    # node with regtest BTC first when needed. Non-fatal: a real issuance/transfer
    # will surface a precise error if the node ends up unfunded.
    def ensure_colorable_utxos!(client)
      fund_node_btc!(client)
      client.create_utxos(up_to: true, num: COLORABLE_UTXOS, size: COLORABLE_UTXO_SIZE, fee_rate: FEE_RATE)
      NodeConfirm.mine! # confirm the new colorable UTXOs (regtest)
      client.refresh_transfers
    rescue LightningClient::Error => e
      Rails.logger.warn("RLN createutxos per utente #{user.id} saltato: #{e.message}")
    end

    def fund_node_btc!(client)
      return unless regtest_bitcoind_available?
      return if client.btc_balance.dig("vanilla", "spendable").to_i >= MIN_VANILLA_SATS

      address = client.address.fetch("address")
      harness = L1::RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET)
      harness.ensure_chain_ready!
      harness.fund_address!(address, sats: FUND_SATS)
    rescue LightningClient::Error => e
      Rails.logger.warn("RLN funding per utente #{user.id} saltato: #{e.message}")
    end

    def regtest_bitcoind_available?
      L1::Bitcoind::Client.new.available?
    rescue StandardError
      false
    end
  end
end
