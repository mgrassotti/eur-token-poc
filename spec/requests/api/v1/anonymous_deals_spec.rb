# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1 anonymous deals", type: :request do
  let(:address) { "bcrt1qanonymousfundingaddress00000000000000" }

  before do
    MarketRate.current.update!(btc_eur_per_btc: 60_000)
  end

  describe "GET /api/v1/deals" do
    it "lists awaiting deals without auth" do
      alice = create(:user)
      alice.btc_account.update!(balance_sats: 10_000_000)
      Budgets::CreateService.call(
        borrower: alice,
        amount_eur_cents: 100_000,
        period_start: Date.current,
        period_end: Date.current + 1.month
      )

      get "/api/v1/deals"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["deals"]).not_to be_empty
      expect(body["deals"].first["status"]).to eq("pending")
    end
  end

  describe "POST /api/v1/deals" do
    it "creates a deal for a guest when commitment PSBT validates" do
      required = Budgets::ReserveRequirement.borrower_required_sats_for(100_000, 60_000)
      outpoints = [ { txid: "ab" * 32, vout: 0, amount_sats: required } ]
      allow(L1::CommitmentPsbtValidator).to receive(:call).and_return(outpoints)

      post "/api/v1/deals", params: {
        deal: {
          amount_eur_cents: 100_000,
          period_start: Date.current.iso8601,
          period_end: (Date.current + 1.month).iso8601,
          funding_address: address,
          commitment_psbt: "cHNidP2fake",
          borrower_name: "Mobile User"
        }
      }, as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("pending")
      expect(body["funding_address"]).to eq(address)
      expect(body["borrower"]["email"]).to start_with("anon+")
      expect(Budget.last.reserved_outpoints).to be_present
    end

    it "rejects create without commitment when anonymous" do
      post "/api/v1/deals", params: {
        deal: {
          amount_eur_cents: 100_000,
          period_start: Date.current.iso8601,
          period_end: (Date.current + 1.month).iso8601,
          funding_address: address
        }
      }, as: :json

      # Without PSBT, falls back to UserWallet balance which is 0 for guest.
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v1/deals/:id/accept" do
    let!(:budget) do
      alice = create(:user)
      alice.btc_account.update!(balance_sats: 10_000_000, reserve_receive_address: "bcrt1qborrower000000000000000000000000")
      Budgets::CreateService.call(
        borrower: alice,
        amount_eur_cents: 100_000,
        period_start: Date.current,
        period_end: Date.current + 1.month
      ).tap do |b|
        b.update!(
          funding_address: alice.btc_account.reserve_receive_address,
          reserved_outpoints: [
            { "txid" => "aa" * 32, "vout" => 0, "amount_sats" => b.borrower_locked_sats + 10_000 }
          ]
        )
      end
    end

    it "accepts anonymously with investor UTXOs (stubbed chain + provision)" do
      allow(L1::UtxoSetValidator).to receive(:call).and_return(1_000_000)

      investor_addr = "bcrt1qinvestor0000000000000000000000000"
      collateral = budget.collateral_sats_at_peg(60_000)
      buffer = Dlc::ContractSetupService::FUNDING_FEE_BUFFER_SATS

      post "/api/v1/deals/#{budget.id}/accept", params: {
        funding_address: investor_addr,
        investor_name: "Investor",
        investor_inputs: [
          { txid: "bb" * 32, vout: 0, amount_sats: collateral + buffer }
        ],
        investor_change_address: investor_addr,
        investor_payout_address: investor_addr,
        investor_identity_pubkey: "02#{"b" * 64}",
        peg_change_address: budget.funding_address,
        peg_identity_pubkey: "02#{"a" * 64}"
      }, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("active")
      expect(body["investor"]["email"]).to start_with("anon+")
    end
  end
end
