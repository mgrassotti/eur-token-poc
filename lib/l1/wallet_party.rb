# frozen_string_literal: true

module L1
  WalletParty = Data.define(:label, :public_key_hex, :wif) do
    def wif_for_signing
      wif
    end
  end
end
