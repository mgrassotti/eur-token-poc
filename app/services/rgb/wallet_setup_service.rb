# frozen_string_literal: true

module Rgb
  class WalletSetupService
    class Error < StandardError; end

    def self.call(user:)
      new(user:).call
    end

    def self.ensure_for!(user)
      wallet_id = call(user: user)
      raise Error, "RGB wallet non configurato per utente #{user.id}" if wallet_id.blank?

      wallet_id
    end

    def initialize(user:)
      @user = user
    end

    def call
      user.reload
      account = user.btc_account || user.create_btc_account!
      wallet_id = account.rgb_wallet_id.presence || Config.wallet_id_for(user)

      response = SidecarClient.instance.create_wallet(
        wallet_id: wallet_id,
        mnemonic: account.rgb_mnemonic
      )

      account.update!(
        rgb_wallet_id: wallet_id,
        rgb_mnemonic: response.fetch("mnemonic")
      )
      account.reload
      user.association(:btc_account).reload

      SidecarClient.instance.setup_wallet(wallet_id)

      account.rgb_wallet_id
    end

    private

    attr_reader :user
  end
end
