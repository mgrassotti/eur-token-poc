# frozen_string_literal: true

module L1
  # Reserve balance for API/mobile: sync from bitcoind when available, else DB cache.
  module ReserveBalance
    module_function

    def sats_for(user)
      sync_quietly(user)
      user.btc_account.reload.balance_sats
    end

    def sync_quietly(user)
      SyncReserveBalanceService.call(user: user)
    rescue Bitcoind::Error, ReserveReceiveAddressService::Error
      nil
    end
  end
end
