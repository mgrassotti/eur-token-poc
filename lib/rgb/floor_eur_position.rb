# frozen_string_literal: true

module Rgb
  class Error < StandardError; end

  FLOOR_EUR_POSITION_SCHEMA = "FloorEURPosition"
  FLOOR_EUR_POSITION_VERSION = 1

  # Owned state per PAYOFF-SPEC §9 / P2P-OPTIONS §7.
  FloorEurPosition = Data.define(
    :assignment_id,
    :deal_id,
    :holder_pubkey,
    :notional_share,
    :strike_eur_per_btc,
    :rate_bps_monthly,
    :blocks_per_month,
    :genesis_height,
    :maturity_height,
    :escrow_outpoint
  ) do
    def validate!
      raise Error, "assignment_id mancante" if assignment_id.blank?
      raise Error, "deal_id mancante" unless deal_id
      raise Error, "holder_pubkey mancante" if holder_pubkey.blank?
      raise Error, "notional_share deve essere positivo" unless notional_share.to_i.positive?
      raise Error, "strike mancante" unless strike_eur_per_btc.to_d.positive?
      raise Error, "escrow_outpoint mancante" if escrow_outpoint.blank?
    end

    def to_h
      {
        assignment_id: assignment_id,
        deal_id: deal_id,
        holder_pubkey: holder_pubkey,
        notional_share: notional_share,
        strike_eur_per_btc: strike_eur_per_btc.to_s,
        rate_bps_monthly: rate_bps_monthly,
        blocks_per_month: blocks_per_month,
        genesis_height: genesis_height,
        maturity_height: maturity_height,
        escrow_outpoint: escrow_outpoint
      }
    end

    def with(**overrides)
      attrs = self.class.members.index_with { |name| public_send(name) }.merge(overrides)
      self.class.new(**attrs)
    end
  end
end
