# frozen_string_literal: true

module Rgb
  module Config
    ISSUER_WALLET_ID = "rgb_issuer"

    # --- Legacy sidecar (deprecated, kept until A.2 removes it) -----------

    def self.sidecar_url
      ENV.fetch("RGB_SIDECAR_URL", "http://127.0.0.1:3030")
    end

    def self.ensure_sidecar!
      return if SidecarClient.instance.available?

      raise SidecarClient::Error,
            "RGB sidecar required at #{sidecar_url} — run ./bin/regtest up"
    end

    def self.wallet_id_for(user)
      "user_#{user.id}"
    end

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
        indexer_url: ENV.fetch("RLN_INDEXER_URL", "electrs:50001"),
        proxy_endpoint: ENV.fetch("RLN_PROXY_ENDPOINT", "rpc://rgb-proxy:3000/json-rpc")
      }
    end

    # Optional Biscuit bearer token (nil when nodes run --disable-authentication).
    def self.rln_token
      ENV["RLN_TOKEN"].presence
    end

    # Raises unless the user's RLN node is reachable. RLN counterpart of
    # ensure_sidecar! for the write paths (issue/transfer/redeem).
    def self.ensure_node!(user)
      return if Nodes.available_for?(user)

      raise LightningClient::Error,
            "RGB node richiesto per utente #{user.id} — esegui ./bin/regtest up"
    end
  end
end
