# frozen_string_literal: true

module Rgb
  # Ensures a user's RGB Lightning Node is ready: initialized, unlocked, with
  # colorable UTXOs and a known pubkey. Returns the node client. Replaces the
  # legacy sidecar wallet bootstrap (one shared process, many wallet_ids).
  class WalletSetupService
    class Error < StandardError; end

    def self.call(user:)
      new(user:).call
    end

    # Returns the ready LightningClient for the user (raises if unavailable).
    def self.ensure_for!(user)
      call(user: user) || raise(Error, "RGB node non configurato per utente #{user.id}")
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
      ensure_utxos!(client)

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

    def ensure_utxos!(client)
      client.create_utxos(num: 4, size: 32_500, fee_rate: 5)
    rescue LightningClient::Error => e
      Rails.logger.warn("RLN createutxos skipped for user #{user.id}: #{e.message}")
    end
  end
end
