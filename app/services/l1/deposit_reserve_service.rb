# frozen_string_literal: true

module L1
  # Incoming transfer from the external wallet → user reserve wallet.
  class DepositReserveService
    BLOCKS_PER_DEPOSIT = 6

    DEMO_DEFAULT_BTC = {
      "alice@example.com" => 0.1,
      "bob@example.com" => 0.2
    }.freeze
    FALLBACK_DEFAULT_BTC = 0.1

    class Error < StandardError; end

    def self.call(user:, amount_sats:)
      new(user:, amount_sats:).call
    end

    def self.default_btc_amount_for(user)
      DEMO_DEFAULT_BTC.fetch(user.email, FALLBACK_DEFAULT_BTC)
    end

    def initialize(user:, amount_sats:)
      @user = user
      @amount_sats = amount_sats.to_i
    end

    def call
      raise Error, "L1 non abilitato (imposta L1_ENABLED=1)" unless L1.enabled?
      raise Error, "Importo non valido" unless @amount_sats.positive?
      validate_bitcoind!

      user_wallet = UserWallet.for(user)
      address = user_wallet.receive_address(label: "external_deposit")

      ExchangeWallet.new.transfer_to!(address: address, amount_sats: @amount_sats)
      advance_simulated_chain!
      user_wallet.sync_balance_to_account!

      user.btc_account.reload
    end

    private

    attr_reader :user

    def advance_simulated_chain!
      ChainState.update_block_height!(ChainState.block_height + BLOCKS_PER_DEPOSIT)
    end

    def validate_bitcoind!
      return if Bitcoind::Client.new.available?

      raise Error, "bitcoind regtest non raggiungibile. Avvia: ./bin/regtest up"
    end
  end
end
