# frozen_string_literal: true

module Dlc
  # Central configuration for the DLC workstream (oracle + ddk node).
  #
  # Defaults target a local Kormir oracle on regtest. The whole DLC path is
  # gated behind `enabled?` so the legacy 2-of-3 escrow remains the default
  # until Workstream B is wired end-to-end.
  module Config
    # --- Oracle (Pythia by default; Kormir/Mycelia supported) ------------

    def self.oracle_url
      ENV.fetch("DLC_ORACLE_URL", "http://127.0.0.1:8000")
    end

    # Which oracle implementation to talk to: "pythia" (default) or "kormir".
    def self.oracle_provider
      ENV.fetch("DLC_ORACLE_PROVIDER", "pythia")
    end

    # Pythia asset pair (snake_case) and API version prefix.
    def self.oracle_asset_pair
      ENV.fetch("DLC_ORACLE_ASSET_PAIR", "btc_usd")
    end

    def self.oracle_version
      ENV.fetch("DLC_ORACLE_VERSION", "v1")
    end

    # Optional bearer token for hardened oracle deployments (Kormir).
    def self.oracle_token
      ENV["DLC_ORACLE_TOKEN"].presence
    end

    # Oracle client instance for the configured provider.
    def self.oracle_client
      case oracle_provider
      when "pythia" then PythiaOracleClient.default
      else OracleClient.default
      end
    end

    # Master switch for the DLC settlement path. While false, settlement uses
    # the legacy 2-of-3 escrow and RGB redemption.
    def self.enabled?
      ENV.fetch("DLC_ENABLED", "false") == "true"
    end

    # --- DLC node (dlcdevkit / ddk shim, REST) ---------------------------

    def self.node_url
      ENV.fetch("DLC_NODE_URL", "http://127.0.0.1:8090")
    end

    def self.node_token
      ENV["DLC_NODE_TOKEN"].presence
    end

    # --- Numeric event parameters (FloorEUR price feed) ------------------
    #
    # FloorEUR settles on the BTC price at maturity. DLC numeric events encode
    # the outcome digit-by-digit (base 2) so CETs can cover ranges; `num_digits`
    # bounds the representable price.

    def self.price_unit
      ENV.fetch("DLC_PRICE_UNIT", "EUR/BTC")
    end

    def self.price_precision
      Integer(ENV.fetch("DLC_PRICE_PRECISION", "0"))
    end

    # 20 base-2 digits => prices up to 1_048_575 (EUR per BTC), ample for regtest.
    def self.num_digits
      Integer(ENV.fetch("DLC_NUM_DIGITS", "20"))
    end

    def self.base
      Integer(ENV.fetch("DLC_NUMERIC_BASE", "2"))
    end
  end
end
