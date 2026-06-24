# frozen_string_literal: true

module Rgb
  # Split assignment N → (N−Δ) + Δ — P2P-OPTIONS §7.1 TransferPosition.
  class TransferPosition
    def self.split(position:, delta:, receiver_pubkey:, receiver_assignment_id: SecureRandom.uuid)
      delta = delta.to_i

      raise Error, "Δ deve essere positivo" unless delta.positive?
      raise Error, "Δ supera notional_share (#{delta} > #{position.notional_share})" if delta > position.notional_share

      remainder = position.notional_share - delta

      sender = position.with(notional_share: remainder)
      receiver = FloorEurPosition.new(
        assignment_id: receiver_assignment_id,
        deal_id: position.deal_id,
        holder_pubkey: receiver_pubkey,
        notional_share: delta,
        strike_eur_per_btc: position.strike_eur_per_btc,
        rate_bps_monthly: position.rate_bps_monthly,
        blocks_per_month: position.blocks_per_month,
        genesis_height: position.genesis_height,
        maturity_height: position.maturity_height,
        escrow_outpoint: position.escrow_outpoint
      )

      sender.validate! if remainder.positive?
      receiver.validate!

      raise Error, "conservazione notional violata" unless sender.notional_share + receiver.notional_share == position.notional_share

      Result.new(sender: sender, receiver: receiver, delta: delta)
    end

    Result = Data.define(:sender, :receiver, :delta)
  end
end
