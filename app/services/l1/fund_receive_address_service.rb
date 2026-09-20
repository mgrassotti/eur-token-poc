# frozen_string_literal: true

module L1
  # Send regtest BTC from the exchange wallet to any receive address.
  # If the address belongs to a known user reserve, sync that account balance.
  # Phase 2: No server-side wallets. Balances updated in DB only.
  class FundReceiveAddressService
    BLOCKS_PER_DEPOSIT = 6

    class Error < StandardError; end

    Result = Struct.new(:txid, :address, :amount_sats, :btc_account, keyword_init: true)

    def self.call(address:, amount_sats:)
      new(address:, amount_sats:).call
    end

    def initialize(address:, amount_sats:)
      @address = address.to_s.strip
      @amount_sats = amount_sats.to_i
    end

    def call
      raise Error, I18n.t("services.l1.fund_receive_address.address_required") if @address.blank?
      raise Error, "Invalid amount" unless @amount_sats.positive?
      validate_bitcoind!

      txid = ExchangeWallet.new.transfer_to!(address: @address, amount_sats: @amount_sats)
      advance_simulated_chain!

      # Phase 2: Update balance in DB when funding a known user address
      account = BtcAccount.find_by(reserve_receive_address: @address)
      if account
        new_balance = account.balance_sats + @amount_sats
        account.update!(balance_sats: new_balance)
        account.reload
      end

      Result.new(txid: txid, address: @address, amount_sats: @amount_sats, btc_account: account)
    rescue ExchangeWallet::Error => e
      raise Error, e.message
    end

    private

    def advance_simulated_chain!
      ChainState.update_block_height!(ChainState.block_height + BLOCKS_PER_DEPOSIT)
    end

    def validate_bitcoind!
      return if Bitcoind::Client.new.available?

      raise Error, I18n.t("services.shared.bitcoind_unreachable")
    end
  end
end
