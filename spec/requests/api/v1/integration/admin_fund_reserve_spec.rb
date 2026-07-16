# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Integration admin fund API", type: :request do
  let(:alice) { create(:user, name: "Alice", email: "alice@example.com") }
  let(:headers) { { "X-Integration-Secret" => "dev-integration-secret" } }
  let(:address) { "bcrt1qaliceintegrationtest" }

  before do
    allow(L1::ReserveReceiveAddressService).to receive(:ensure!).with(user: alice).and_return(address)
  end

  describe "POST /api/v1/integration/admin_fund_reserve" do
    it "funds reserve when pasted address matches" do
      allow(L1::DepositReserveService).to receive(:call).with(user: alice, amount_sats: 1_000_000) do
        alice.btc_account.update!(balance_sats: 1_000_000)
      end

      post "/api/v1/integration/admin_fund_reserve",
           params: { user_email: alice.email, receive_address: address, amount_btc: "0.01" },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["balance_sats"]).to eq(1_000_000)
      expect(body["amount_sats"]).to eq(1_000_000)
    end

    it "rejects mismatched pasted address" do
      post "/api/v1/integration/admin_fund_reserve",
           params: { user_email: alice.email, receive_address: "bcrt1qwrong", amount_btc: "0.01" },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).fetch("error")).to eq("address_mismatch")
    end

    it "rejects missing integration secret" do
      post "/api/v1/integration/admin_fund_reserve",
           params: { user_email: alice.email, amount_btc: "0.01" },
           as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
