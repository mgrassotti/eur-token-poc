# frozen_string_literal: true

module DemoData
  class ResetService
    ALICE_SATS = 10_000_000 # 0.1 BTC
    BOB_SATS = 20_000_000   # 0.2 BTC
    DEFAULT_BTC_EUR_PER_BTC = 60_000

    def self.call
      new.call
    end

    def call
      ActiveRecord::Base.transaction do
        clear_ledger!
        reset_balances!
        reset_market_rate!
      end
    end

    private

    def clear_ledger!
      Settlement.delete_all
      TokenTransfer.delete_all
      TokenAccount.delete_all
      CollateralLock.delete_all
      Budget.delete_all
    end

    def reset_balances!
      BtcAccount.update_all(balance_sats: 0)
      alice.btc_account.update!(balance_sats: ALICE_SATS)
      bob.btc_account.update!(balance_sats: BOB_SATS)
    end

    def reset_market_rate!
      MarketRate.current.update!(
        btc_eur_per_btc: DEFAULT_BTC_EUR_PER_BTC,
        set_by: User.find_by(email: "admin@example.com")
      )
    end

    def alice
      @alice ||= User.find_by!(email: "alice@example.com")
    end

    def bob
      @bob ||= User.find_by!(email: "bob@example.com")
    end
  end
end
