# frozen_string_literal: true

module Rgb
  module Config
    # Host-port → compose peer listen addr (nodes connect to each other on the
    # docker network, not via published host ports).
    RLN_PEER_BY_API_PORT = {
      3001 => "rln-alice:9735",
      3002 => "rln-bob:9735",
      3003 => "rln-claude:9735",
      3004 => "rln-david:9735",
      3005 => "rln-issuer:9735"
    }.freeze

    # --- RGB Lightning Node (RLN) ----------------------------------------

    # Password used to init/unlock demo nodes. Real deployments override per node.
    def self.rln_password
      ENV.fetch("RLN_PASSWORD", "regtestpassword")
    end

    # URL of the issuer/treasury RLN node (redemption destination, optional
    # genesis fallback). Per-user node URLs live on BtcAccount#rln_node_url.
    # PoC MAT liquidity hub = this issuer node.
    def self.rln_issuer_url
      ENV.fetch("RLN_ISSUER_URL", "http://127.0.0.1:3005")
    end

    def self.rln_hub_url
      ENV.fetch("RLN_HUB_URL", rln_issuer_url)
    end

    # Peer listen address of the hub as reached from other RLN containers.
    def self.rln_hub_peer_addr
      ENV.fetch("RLN_HUB_PEER_ADDR", "rln-issuer:9735")
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

    # When true, user↔user EURT uses RGB-LN via the hub instead of /sendrgb.
    def self.transfer_via_ln?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("RGB_TRANSFER_VIA_LN", "0"))
    end

    # Peer host:port for a node API URL (compose-internal).
    def self.rln_peer_addr_for_url(url)
      port = URI.parse(url.to_s).port
      RLN_PEER_BY_API_PORT[port] || ENV["RLN_PEER_ADDR"].presence ||
        raise(LightningClient::Error, "No RLN peer addr mapping for #{url}")
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
