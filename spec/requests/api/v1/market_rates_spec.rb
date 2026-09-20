# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 market rate", type: :request do
  it "returns the current BTC/EUR rate without authentication" do
    MarketRate.current.update!(btc_eur_per_btc: 50_000)

    get "/api/v1/market_rate", as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["btc_eur_per_btc"]).to eq(50_000.0)
    expect(body["set"]).to be(true)
  end
end
