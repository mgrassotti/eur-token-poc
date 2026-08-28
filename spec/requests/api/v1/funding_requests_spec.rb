# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v1 funding requests", type: :request do
  let(:address) { "bcrt1qalicefundingaddress000000000000001" }

  before { MarketRate.current.update!(btc_eur_per_btc: 50_000) }

  it "creates a saver request and returns the MAT IBAN" do
    post "/api/v1/funding_requests", params: {
      funding_request: {
        role: "saver",
        amount_eur_cents: 100_000,
        receive_address: address,
        payout_mode: "keep_btc",
        display_name: "Alice"
      }
    }, as: :json

    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body["role"]).to eq("saver")
    expect(body["status"]).to eq("awaiting_deposit")
    expect(body["collection_iban"]).to eq(BankAccount::DEFAULT_IBAN)
    expect(body["rate_bps_monthly"]).to eq(100)
  end

  it "lists requests by receive address" do
    Funding::CreateRequest.call(
      role: :saver,
      amount_eur_cents: 50_000,
      receive_address: address,
      payout_mode: :reinvest,
      display_name: "Alice"
    )

    get "/api/v1/funding_requests", params: { address: address }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["requests"].size).to eq(1)
  end

  it "queues a request when UTXOs are submitted" do
    request = Funding::CreateRequest.call(
      role: :investor,
      amount_eur_cents: 100_000,
      receive_address: address,
      payout_mode: :keep_btc,
      display_name: "Bob"
    )

    post "/api/v1/funding_requests/#{request.id}/submit_utxos", params: {
      inputs: [ { txid: "aa" * 32, vout: 0, amount_sats: 3_000_000 } ],
      change_address: "#{address}c",
      identity_pubkey: "02#{"b" * 64}"
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["status"]).to eq("queued")
  end
end
