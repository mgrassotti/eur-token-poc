# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Relay API v1", type: :request do
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  def login(user)
    post "/api/v1/auth/login", params: { email: user.email, password: "password" }
    JSON.parse(response.body).fetch("token")
  end

  describe "POST /api/v1/auth/login" do
    it "returns a bearer token and user payload" do
      post "/api/v1/auth/login", params: { email: alice.email, password: "password" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["token"]).to be_present
      expect(body.dig("user", "email")).to eq(alice.email)
    end

    it "rejects invalid credentials" do
      post "/api/v1/auth/login", params: { email: alice.email, password: "wrong" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/dashboard" do
    let(:token) { login(alice) }

    before do
      MarketRate.current.update!(btc_eur_per_btc: 50_000)
      alice.btc_account.update!(balance_sats: 5_000_000)
    end

    it "returns dashboard aggregates" do
      get "/api/v1/dashboard", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["schema_version"]).to eq(1)
      expect(body.dig("market_rate", "btc_eur_per_btc")).to eq(50_000.0)
      expect(body.dig("user", "name")).to eq("Alice")
    end
  end

  describe "deals lifecycle" do
    let(:token) { login(alice) }

    before do
      MarketRate.current.update!(btc_eur_per_btc: 50_000)
      alice.btc_account.update!(balance_sats: 5_000_000)
    end

    it "creates, lists, and shows a deal" do
      post "/api/v1/deals",
           params: {
             deal: {
               amount_eur_cents: 100_000,
               period_start: "2026-01-01",
               period_end: "2026-02-01"
             }
           },
           headers: headers

      expect(response).to have_http_status(:created)
      deal_id = JSON.parse(response.body).fetch("id")

      get "/api/v1/deals", headers: headers
      ids = JSON.parse(response.body).fetch("deals").map { |d| d["id"] }
      expect(ids).to include(deal_id)

      get "/api/v1/deals/#{deal_id}", headers: headers
      expect(JSON.parse(response.body).fetch("status")).to eq("pending")
    end
  end

  describe "GET /api/v1/deals/:id/settlement" do
    let(:token) { login(alice) }
    let(:budget) do
      create(
        :budget,
        borrower: alice,
        amount_eur_cents: 100_000,
        peg_eur_per_btc: 50_000,
        status: :active,
        period_start: Date.new(2026, 1, 1),
        period_end: Date.new(2026, 2, 1)
      )
    end

    before do
      MarketRate.current.update!(btc_eur_per_btc: 50_000)
      CollateralLock.create!(budget: budget, amount_sats: 3_975_000, locked_at: Time.current)
      TokenAccount.create!(budget: budget, user: alice, balance_cents: 100_000)
    end

    it "returns a settlement preview with FloorEUR payoff" do
      get "/api/v1/deals/#{budget.id}/settlement", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("preview")
      expect(body.dig("payoff", "liability_eur_cents")).to eq(101_000)
      expect(body.dig("payoff", "total_holder_sats")).to eq(2_020_000)

      inputs = body.fetch("calculation_inputs")
      expect(inputs["notional_eur_cents"]).to eq(budget.notional_eur_cents)
      expect(inputs["notional_total_cents"]).to eq(budget.amount_eur_cents)
      expect(inputs["holder_shares_cents"]).to eq([100_000])
      expect(inputs["spot_eur_per_btc"]).to eq(50_000)
      expect(inputs["rate_bps_monthly"]).to eq(budget.rate_bps_monthly)
      expect(inputs["months_elapsed"]).to eq(budget.symbolic_months_duration)
      expect(inputs["escrow_total_sats"]).to eq(budget.pool_sats)
      expect(inputs["mining_fee_sats"]).to eq(Budget::ESTIMATED_SETTLEMENT_FEE_SATS)
    end
  end

  describe "GET /api/v1/market_rate" do
    let(:token) { login(bob) }

    it "returns the current market rate" do
      MarketRate.current.update!(btc_eur_per_btc: 55_000)

      get "/api/v1/market_rate", headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).fetch("btc_eur_per_btc")).to eq(55_000.0)
    end
  end
end
