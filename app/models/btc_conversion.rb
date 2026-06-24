# frozen_string_literal: true

module BtcConversion
  SATS_PER_BTC = 100_000_000

  module_function

  def eur_cents_to_sats(eur_cents, eur_per_btc)
    eur = eur_cents / 100.0
    btc = eur / eur_per_btc.to_d
    (btc * SATS_PER_BTC).round
  end

  def token_cents_to_sats(token_cents, peg_eur_per_btc)
    eur_cents_to_sats(token_cents, peg_eur_per_btc)
  end

  # Returns [holder_sats, fx_to_investor_sats] for settlement.
  def settlement_holder_sats(token_cents, peg_eur_per_btc, end_eur_per_btc)
    peg_sats = token_cents_to_sats(token_cents, peg_eur_per_btc)
    current_sats = token_cents_to_sats(token_cents, end_eur_per_btc)
    fx_to_investor_sats = (peg_sats - current_sats).abs
    holder_sats = current_sats

    [holder_sats, fx_to_investor_sats]
  end

  def btc_to_sats(btc)
    (btc.to_d * SATS_PER_BTC).round
  end

  def sats_to_btc(sats)
    sats.to_d / SATS_PER_BTC
  end

  def sats_to_eur(sats, eur_per_btc)
    sats_to_btc(sats) * eur_per_btc.to_d
  end

  # Importo € massimo bloc cabile senza superare i sats disponibili (arrotondamento per difetto).
  def max_eur_cents_for_sats(sats, eur_per_btc)
    return 0 unless sats.positive? && eur_per_btc.to_d.positive?

    max_eur = sats_to_eur(sats, eur_per_btc)
    (max_eur * 100).floor
  end

  def format_eur_amount(amount)
    format("€%.2f", amount)
  end

  def format_btc(sats)
    format("%.8f BTC", sats_to_btc(sats))
  end

  def format_eur(cents)
    format("€%.2f", cents / 100.0)
  end
end
