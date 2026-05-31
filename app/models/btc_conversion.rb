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

  def sats_to_btc(sats)
    sats.to_d / SATS_PER_BTC
  end

  def format_btc(sats)
    format("%.8f BTC", sats_to_btc(sats))
  end

  def format_eur(cents)
    format("%.2f EUR", cents / 100.0)
  end
end
