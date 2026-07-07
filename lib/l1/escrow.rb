# frozen_string_literal: true

module L1
  # 2-of-2 P2WSH collateral lock (BIP67 pubkey sort) between peg + investor.
  # Settlement is handled by the DLC (oracle-attested CET); this UTXO only locks
  # the reserve collateral on-chain (recoverable via the timelocked refund path).
  class Escrow
    REQUIRED_SIGNATURES = 2
    TOTAL_KEYS = 2

    Result = Data.define(:address, :redeem_script_hex, :witness_script_hex, :pubkeys_hex)

    def self.from_keys(peg_party:, investor:, client: Bitcoind::Client.new)
      pubkeys = [peg_party.public_key_hex, investor.public_key_hex].sort
      response = client.call(
        "createmultisig",
        REQUIRED_SIGNATURES,
        pubkeys,
        "bech32"
      )

      Result.new(
        address: response.fetch("address"),
        redeem_script_hex: response.fetch("redeemScript"),
        witness_script_hex: response.fetch("redeemScript"),
        pubkeys_hex: pubkeys
      )
    end
  end
end
