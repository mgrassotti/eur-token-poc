# frozen_string_literal: true

module L1
  # 2-of-3 P2WSH escrow (BIP67 pubkey sort) — MULTISIG-SPEC §2, §4.
  class Escrow
    REQUIRED_SIGNATURES = 2
    TOTAL_KEYS = 3

    Result = Data.define(:address, :redeem_script_hex, :witness_script_hex, :pubkeys_hex)

    def self.from_keys(peg_party:, investor:, bot:, client: Bitcoind::Client.new)
      pubkeys = [peg_party.public_key_hex, investor.public_key_hex, bot.public_key_hex].sort
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
