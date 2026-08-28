# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v1 receive requests", type: :request, skip: "MVP savings: P2P receive requests unplugged" do
  let(:claude) { create(:user, name: "Claude") }
  let(:alice) { create(:user, name: "Alice") }
  let(:headers) { { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" } }

  def login(user)
    post "/api/v1/auth/login", params: { email: user.email, password: "password" }
    JSON.parse(response.body).fetch("token")
  end

  describe "POST /api/v1/receive_requests" do
    let(:token) { login(claude) }

    it "creates a short-lived QR payment request" do
      request_record = ReceiveRequest.new(
        user: claude,
        public_id: "req-uuid",
        amount_eur_cents: 2_500,
        recipient_id: "utxob:blinded",
        invoice: "rgb:invoice",
        expires_at: 15.minutes.from_now
      )
      allow(Rgb::ReceiveRequestService).to receive(:call).and_return(request_record)

      post "/api/v1/receive_requests",
           params: { amount_eur_cents: 2_500 }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq("req-uuid")
      expect(body["qr_payload"]).to include("mat:pay/1?")
      expect(body["qr_payload"]).to include("rid=req-uuid")
      expect(body.dig("user", "name")).to eq("Claude")
      expect(body["amount_eur_cents"]).to eq(2_500)
    end
  end

  describe "GET /api/v1/receive_requests/:id" do
    let(:token) { login(alice) }
    let!(:request_record) do
      ReceiveRequest.create!(
        user: claude,
        amount_eur_cents: 1_000,
        recipient_id: "utxob:x",
        invoice: "rgb:x",
        expires_at: 10.minutes.from_now
      )
    end

    it "returns the request for the payer" do
      get "/api/v1/receive_requests/#{request_record.public_id}", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(request_record.public_id)
      expect(body.dig("user", "id")).to eq(claude.id)
    end
  end

  describe "POST /api/v1/transfers with receive_request_id" do
    let(:token) { login(alice) }
    let!(:request_record) do
      ReceiveRequest.create!(
        user: claude,
        amount_eur_cents: 2_500,
        recipient_id: "utxob:from-qr",
        invoice: "rgb:from-qr",
        expires_at: 10.minutes.from_now
      )
    end

    before do
      allow(Tokens::Spendable).to receive(:total_cents_for).with(alice).and_return(10_000)
      allow(Tokens::WalletTransferService).to receive(:call).and_return(
        [Tokens::WalletTransferService::TransferPart.new(budget: create(:budget, borrower: alice, status: :active), amount_cents: 2_500)]
      )
    end

    it "pays the QR request and marks it paid" do
      post "/api/v1/transfers",
           params: { receive_request_id: request_record.public_id }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      expect(Tokens::WalletTransferService).to have_received(:call).with(
        hash_including(
          from_user: alice,
          to_user: claude,
          amount_cents: 2_500,
          rgb_recipient_id: "utxob:from-qr"
        )
      )
      expect(request_record.reload).to be_paid
      expect(request_record.paid_by_user_id).to eq(alice.id)
    end

    it "rejects an expired request" do
      request_record.update!(expires_at: 1.minute.ago)

      post "/api/v1/transfers",
           params: { receive_request_id: request_record.public_id }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Tokens::WalletTransferService).not_to have_received(:call)
    end
  end
end
