# frozen_string_literal: true

module L1
  # Stable regtest receive address for a user's reserve wallet (mobile QR / admin deposit).
  class ReserveReceiveAddressService
    LABEL = "reserve_receive"

    class Error < StandardError; end

    def self.ensure!(user:)
      new(user:).ensure!
    end

    def initialize(user:)
      @user = user
      @btc_account = user.btc_account
    end

    def ensure!
      return @btc_account.reserve_receive_address if @btc_account.reserve_receive_address.present?

      validate_bitcoind!
      address = UserWallet.for(@user).receive_address(label: LABEL)
      @btc_account.update!(reserve_receive_address: address)
      address
    rescue Bitcoind::Error => e
      raise Error, e.message
    end

    private

    def validate_bitcoind!
      return if Bitcoind::Client.new.available?

      raise Error, I18n.t("services.shared.bitcoind_unreachable")
    end
  end
end
