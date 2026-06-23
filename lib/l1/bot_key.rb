# frozen_string_literal: true

module L1
  # Per-deal bot signing key (facilitator 2-of-3) — MULTISIG-SPEC §2.
  class BotKey
    def self.generate
      new(KeyMaterial.generate)
    end

    def initialize(key_material)
      @key_material = key_material
    end

    def wif
      @key_material.wif
    end

    def public_key_hex
      @key_material.public_key_hex
    end
  end
end
