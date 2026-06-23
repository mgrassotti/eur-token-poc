# frozen_string_literal: true

module L1
  # Il conto di riserva in DB è il saldo mostrato in UI; si accredita solo su deposito confermato.
  # (Il wallet regtest può contenere UTXO legacy da test — non usare getbalance come fonte di verità.)
  class SyncReserveBalanceService
    def self.call(user:)
      user.btc_account
    end
  end
end
