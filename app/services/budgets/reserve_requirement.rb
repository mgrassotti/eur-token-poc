# frozen_string_literal: true

module Budgets
  # Requisiti di riserva e massimo importo ricaricabile al cambio corrente (saldo on-chain).
  module ReserveRequirement
    module_function

    def borrower_sats_for(amount_eur_cents, eur_per_btc)
      BtcConversion.eur_cents_to_sats(amount_eur_cents, eur_per_btc)
    end

    def investor_collateral_sats_for(budget, eur_per_btc)
      budget.collateral_sats_at_peg(eur_per_btc)
    end

    def investor_sats_for(budget, eur_per_btc, include_l1_fee: true)
      sats = investor_collateral_sats_for(budget, eur_per_btc)
      include_l1_fee ? sats + L1::FundingPsbtService::ESTIMATED_FEE_SATS : sats
    end

    def available_sats_for(user)
      L1::UserWallet.for(user).spendable_sats
    end

    def max_eur_cents_for(user)
      return 0 unless MarketRate.current.set?

      sats = available_sats_for(user)
      return 0 unless sats.positive?

      BtcConversion.max_eur_cents_for_sats(sats, MarketRate.current.btc_eur_per_btc)
    end

    def max_eur_for(user)
      max_eur_cents_for(user) / 100.0
    end

    def insufficient_message(label:, required_sats:, available_sats:, eur_per_btc:)
      required_eur = BtcConversion.sats_to_eur(required_sats, eur_per_btc)
      available_eur = BtcConversion.sats_to_eur(available_sats, eur_per_btc)
      "Saldo insufficiente sul conto di riserva per #{label} " \
        "(servono #{required_sats} sats ≈ €#{format('%.2f', required_eur)} @ #{eur_per_btc.to_i}, " \
        "disponibili #{available_sats} sats ≈ €#{format('%.2f', available_eur)})"
    end
  end
end
