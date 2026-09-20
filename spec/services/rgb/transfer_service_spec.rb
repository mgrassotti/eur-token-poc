# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rgb::TransferService, skip: "MVP savings: RGB unplugged" do
  let(:alice) { create(:user) }
  let(:claude) { create(:user) }
  let(:budget) { create(:budget, borrower: alice, rgb_asset_id: "rgb_stub") }
  let(:rgb_result) do
    Rgb::TransferResult.new(
      txid: "deadbeef",
      recipient_id: "rcp1",
      asset_id: "rgb_stub",
      amount: 400_000
    )
  end

  before do
    allow(Rgb::TransferService).to receive(:call).and_call_original
    allow(Rgb::Config).to receive(:ensure_node!)
    allow(Rgb::LibTransferService).to receive(:call).and_return(rgb_result)
  end

  it "delegates to LibTransferService and returns the on-chain result" do
    result = described_class.call(
      budget: budget,
      from_user: alice,
      to_user: claude,
      amount_cents: 400_000
    )

    expect(Rgb::LibTransferService).to have_received(:call).with(
      budget: budget,
      from_user: alice,
      to_user: claude,
      amount_cents: 400_000,
      rgb_recipient_id: nil
    )
    expect(result).to eq(rgb_result)
  end
end
