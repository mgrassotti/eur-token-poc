# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reserve API", type: :request do
  let(:user) { create(:user, name: "Bob") }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }
  let(:test_address) { "bcrt1qtestaddress" }

  def login(user)
    post "/api/v1/auth/login", params: { email: user.email, password: "password" }
    JSON.parse(response.body).fetch("token")
  end

  describe "GET /api/v1/reserve" do
    let(:token) { login(user) }

    it "returns the stored receive address" do
      # Phase 2: Address is stored in the database
      user.btc_account.update!(reserve_receive_address: test_address, balance_sats: 1_000_000)

      get "/api/v1/reserve", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["receive_address"]).to eq(test_address)
      expect(body["network"]).to eq("regtest")
      expect(body["balance_sats"]).to eq(1_000_000)
    end
  end

  describe "POST /api/v1/reserve/sync" do
    let(:token) { login(user) }

    it "syncs balance (no-op in Phase 2, mobile clients sync via BDK)" do
      user.btc_account.update!(balance_sats: 5_000_000)

      post "/api/v1/reserve/sync", headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).fetch("balance_sats")).to eq(5_000_000)
    end
  end
end
