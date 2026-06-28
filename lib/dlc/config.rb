# frozen_string_literal: true

module Dlc
  # Central configuration for the DLC workstream (oracle + ddk node).
  #
  # Defaults target a local Kormir oracle on regtest. The whole DLC path is
  # gated behind `enabled?` so the legacy 2-of-3 escrow remains the default
  # until Workstream B is wired end-to-end.
  module Config
    # --- Oracle (Kormir / Mycelia Signal, REST) --------------------------

    def self.oracle_url
      ENV.fetch("DLC_ORACLE_URL", "http://127.0.0.1:8080")
    end

    # Optional bearer token for hardened oracle deployments.
    def self.oracle_token
      ENV["DLC_ORACLE_TOKEN"].presence
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
