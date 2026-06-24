# frozen_string_literal: true

module Rgb
  module HolderIdentity
    def self.pubkey_for(user)
      account = user.btc_account || user.create_btc_account!
      return account.escrow_identity_pubkey if account.escrow_identity_pubkey.present?

      pubkey = L1::UserWallet.for(user).identity_pubkey
      if pubkey.blank?
        pubkey = format("02%064x", user.id)
        account.update!(escrow_identity_pubkey: pubkey)
      end

      pubkey
    end
  end
end
