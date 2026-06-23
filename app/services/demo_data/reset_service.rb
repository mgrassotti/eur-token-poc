# frozen_string_literal: true

module DemoData
  class ResetService
    DEMO_USERS = [
      { name: "Admin", email: "admin@example.com", admin: true },
      { name: "Alice", email: "alice@example.com", admin: false },
      { name: "Bob", email: "bob@example.com", admin: false },
      { name: "Claude", email: "claude@example.com", admin: false },
      { name: "David", email: "david@example.com", admin: false }
    ].freeze

    DEMO_PASSWORD = "password"
    DEFAULT_BTC_EUR_PER_BTC = 50_000

    def self.call
      new.call
    end

    def call
      ActiveRecord::Base.transaction do
        clear_ledger!
        ensure_demo_users!
        reset_balances!
        reset_market_rate!
      end
    end

    private

    def clear_ledger!
      InvestorYieldPayout.delete_all
      Settlement.delete_all
      TokenTransfer.delete_all
      TokenAccount.delete_all
      CollateralLock.delete_all
      Budget.delete_all
    end

    def ensure_demo_users!
      @demo_users = DEMO_USERS.to_h do |attrs|
        user = User.find_or_initialize_by(email: attrs[:email])
        user.assign_attributes(
          name: attrs[:name],
          password: DEMO_PASSWORD,
          password_confirmation: DEMO_PASSWORD,
          admin: attrs[:admin]
        )
        user.save!
        [attrs[:email], user]
      end
    end

    def reset_balances!
      BtcAccount.update_all(balance_sats: 0, bitcoind_wallet_name: nil)
    end

    def reset_market_rate!
      MarketRate.current.update!(
        btc_eur_per_btc: DEFAULT_BTC_EUR_PER_BTC,
        bitcoin_block_height: ChainState.estimate_block_height,
        set_by: demo_users.fetch("admin@example.com")
      )
    end

    def demo_users
      @demo_users ||= DEMO_USERS.to_h do |attrs|
        [attrs[:email], User.find_by!(email: attrs[:email])]
      end
    end
  end
end
