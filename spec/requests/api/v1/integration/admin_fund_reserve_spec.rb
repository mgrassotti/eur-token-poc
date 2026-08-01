# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Integration admin fund API", type: :request do
  let(:headers) { { "X-Integration-Secret" => "dev-integration-secret" } }
  let(:address) { "bcrt1qaliceintegrationtest" }

  describe "POST /api/v1/integration/admin_fund_reserve" do
    it "funds any receive address without user lookup" do
      allow(L1::FundReceiveAddressService).to receive(:call).with(address: address, amount_sats: 1_000_000).and_return(
        L1::FundReceiveAddressService::Result.new(
          txid: "test_txid",
          address: address,
          amount_sats: 1_000_000,
          btc_account: nil
        )
      )

      post "/api/v1/integration/admin_fund_reserve",
           params: { receive_address: address, amount_btc: "0.01" },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["receive_address"]).to eq(address)
      expect(body["amount_sats"]).to eq(1_000_000)
      expect(body["txid"]).to eq("test_txid")
    end

    it "rejects blank receive address" do
      post "/api/v1/integration/admin_fund_reserve",
           params: { receive_address: "  ", amount_btc: "0.01" },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).fetch("error")).to eq("address_required")
    end

    it "rejects missing integration secret" do
      post "/api/v1/integration/admin_fund_reserve",
           params: { receive_address: address, amount_btc: "0.01" },
           as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
