# frozen_string_literal: true

module Rgb
  module Config
    # --- RGB Lightning Node (RLN) ----------------------------------------

    # Password used to init/unlock demo nodes. Real deployments override per node.
    def self.rln_password
      ENV.fetch("RLN_PASSWORD", "regtestpassword")
    end

    # URL of the issuer/treasury RLN node (redemption destination, optional
    # genesis fallback). Per-user node URLs live on BtcAccount#rln_node_url.
    def self.rln_issuer_url
      ENV.fetch("RLN_ISSUER_URL", "http://127.0.0.1:3005")
    end

    # bitcoind / indexer / proxy coordinates passed to /unlock. On the compose
    # network the nodes reach the shared services by service name.
    def self.rln_unlock_params
      {
        bitcoind_rpc_username: ENV.fetch("RLN_BITCOIND_USER", "regtest"),
        bitcoind_rpc_password: ENV.fetch("RLN_BITCOIND_PASS", "regtest"),
        bitcoind_rpc_host: ENV.fetch("RLN_BITCOIND_HOST", "bitcoind"),
        bitcoind_rpc_port: Integer(ENV.fetch("RLN_BITCOIND_PORT", "18443")),
        indexer_url: ENV.fetch("RLN_INDEXER_URL", "tcp://electrs:50001"),
        proxy_endpoint: ENV.fetch("RLN_PROXY_ENDPOINT", "rpc://rgb-proxy:3000/json-rpc")
      }
    end

    # Optional Biscuit bearer token (nil when nodes run --disable-authentication).
    def self.rln_token
      ENV["RLN_TOKEN"].presence
    end

    # Raises unless the user's RLN node daemon answers. Guards the RGB write
    # paths (issue/transfer/redeem); the services unlock the node themselves.
    def self.ensure_node!(user)
      return if Nodes.reachable_for?(user)

      raise LightningClient::Error,
            "RGB node richiesto per utente #{user.id} — esegui ./bin/regtest up"
    end
  end
end
