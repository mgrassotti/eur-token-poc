# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rgb::TransferPosition do
  let(:position) do
    Rgb::FloorEurPosition.new(
      assignment_id: "asg-alice",
      deal_id: 1,
      holder_pubkey: "02#{"a" * 64}",
      notional_share: 1_000_000,
      strike_eur_per_btc: 50_000,
      rate_bps_monthly: 100,
      blocks_per_month: Budget::BLOCKS_PER_MONTH,
      genesis_height: 100,
      maturity_height: 10_000,
      escrow_outpoint: "abc:0"
    )
  end

  it "splits 40% to receiver preserving notional" do
    result = described_class.split(
      position: position,
      delta: 400_000,
      receiver_pubkey: "02#{"b" * 64}",
      receiver_assignment_id: "asg-claude"
    )

    expect(result.sender.notional_share).to eq(600_000)
    expect(result.receiver.notional_share).to eq(400_000)
    expect(result.sender.notional_share + result.receiver.notional_share).to eq(position.notional_share)
    expect(result.receiver.holder_pubkey).to eq("02#{"b" * 64}")
    expect(result.receiver.escrow_outpoint).to eq(position.escrow_outpoint)
  end

  it "rejects delta greater than notional" do
    expect do
      described_class.split(position: position, delta: 1_000_001, receiver_pubkey: "02#{"b" * 64}")
    end.to raise_error(Rgb::Error, /supera notional_share/)
  end
end
