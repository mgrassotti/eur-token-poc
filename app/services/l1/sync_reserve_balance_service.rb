# frozen_string_literal: true

module L1
  # Allinea il conto di riserva DB al saldo spendibile del wallet regtest utente.
  class SyncReserveBalanceService
    def self.call(user:)
      new(user:).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      UserWallet.for(user).sync_balance_to_account!
    end

    private

    attr_reader :user
  end
end
