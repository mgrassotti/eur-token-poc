# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::SubmitUtxos do
  let(:alice) { create(:user, name: "Alice") }
  let(:address) { "bcrt1qalicefundingaddress000000000000001" }

  let(:request) do
    FundingRequest.create!(
      user: alice,
      role: :saver,
      status: :awaiting_deposit,
      amount_eur_cents: 100_000,
      remaining_eur_cents: 100_000,
      payout_mode: :keep_btc,
      receive_address: address
    )
  end

  before do
    MarketRate.current.update!(btc_eur_per_btc: 50_000)
    allow(Funding::MatchingService).to receive(:call)
  end

  it "stores the on-device fund pubkey and queues the request" do
    described_class.call(
      request: request,
      inputs: [ { txid: "aa" * 32, vout: 0, amount_sats: 3_000_000 } ],
      change_address: "#{address}c",
      identity_pubkey: "02#{"ab" * 32}"
    )

    expect(request.reload).to be_queued
    expect(request.identity_pubkey).to eq("02#{"ab" * 32}")
    expect(Funding::MatchingService).to have_received(:call)
  end

  it "rejects a missing fund pubkey" do
    expect do
      described_class.call(
        request: request,
        inputs: [ { txid: "aa" * 32, vout: 0, amount_sats: 3_000_000 } ],
        change_address: "#{address}c"
      )
    end.to raise_error(described_class::Error, /identity_pubkey required/)
  end

  it "rejects a placeholder that is not a compressed pubkey" do
    expect do
      described_class.call(
        request: request,
        inputs: [ { txid: "aa" * 32, vout: 0, amount_sats: 3_000_000 } ],
        change_address: "#{address}c",
        identity_pubkey: "02peg"
      )
    end.to raise_error(described_class::Error, /compressed secp256k1/)
  end
end
