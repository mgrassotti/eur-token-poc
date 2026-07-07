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

    # Maps each demo user to its dedicated RGB Lightning Node (host ports defined
    # in docker-compose.regtest.yml). Admin has no node (does not transact RGB);
    # the issuer/treasury node lives at Rgb::Config.rln_issuer_url (3005).
    RLN_NODE_URLS = {
      "alice@example.com" => "http://127.0.0.1:3001",
      "bob@example.com" => "http://127.0.0.1:3002",
      "claude@example.com" => "http://127.0.0.1:3003",
      "david@example.com" => "http://127.0.0.1:3004"
    }.freeze

    def self.call
      new.call
    end

    def call
      ActiveRecord::Base.transaction do
        clear_ledger!
        remove_non_demo_users!
        ensure_demo_users!
        reset_balances!
        reset_market_rate!
      end

      L1::RegtestResetService.call
    end

    private

    def clear_ledger!
      InvestorYieldPayout.delete_all
      Settlement.delete_all
      DlcSettlement.delete_all
      DlcContract.delete_all
      TokenTransfer.delete_all
      RgbAssignment.delete_all
      TokenAccount.delete_all
      CollateralLock.delete_all
      Budget.delete_all
    end

    def remove_non_demo_users!
      demo_emails = DEMO_USERS.pluck(:email)
      MarketRate.update_all(set_by_id: nil)
      User.where.not(email: demo_emails).destroy_all
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
      BtcAccount.find_each do |account|
        account.update!(
          balance_sats: 0,
          bitcoind_wallet_name: fresh_wallet_name_for(account.user_id),
          escrow_identity_wif: nil,
          escrow_identity_pubkey: nil,
          rgb_wallet_id: nil,
          rgb_mnemonic: nil,
          node_pubkey: nil,
          rln_node_url: RLN_NODE_URLS[account.user.email]
        )
      end
    end

    def fresh_wallet_name_for(user_id)
      "user_#{user_id}_#{Time.current.to_i}"
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
