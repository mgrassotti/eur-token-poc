# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reserve API", type: :request do
  let(:user) { create(:user, name: "Bob") }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  def login(user)
    post "/api/v1/auth/login", params: { email: user.email, password: "password" }
    JSON.parse(response.body).fetch("token")
  end

  describe "GET /api/v1/reserve" do
    let(:token) { login(user) }

    it "returns a stable regtest receive address" do
      allow(L1::ReserveReceiveAddressService).to receive(:ensure!).with(user: user).and_return("bcrt1qtestaddress")
      user.btc_account.update!(balance_sats: 1_000_000)

      get "/api/v1/reserve", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["receive_address"]).to eq("bcrt1qtestaddress")
      expect(body["network"]).to eq("regtest")
      expect(body["balance_sats"]).to eq(1_000_000)
    end
  end

  describe "POST /api/v1/reserve/sync" do
    let(:token) { login(user) }

    it "syncs balance from bitcoind wallet" do
      allow(L1::SyncReserveBalanceService).to receive(:call).with(user: user) do
        user.btc_account.update!(balance_sats: 5_000_000)
      end

      post "/api/v1/reserve/sync", headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).fetch("balance_sats")).to eq(5_000_000)
    end
  end
end
