# frozen_string_literal: true

require "rails_helper"

RSpec.describe L1::DealSigning do
  let(:bob) { create(:user) }
  let(:budget) do
    setup_active_budget!(borrower: create(:user), investor: bob, amount_eur_cents: 100_000, peg: 50_000)
  end

  it "reads investor wif from recovery package when present" do
    budget.update!(
      investor_pubkey: "02#{"b" * 64}",
      recovery_package: {
        "party_signing" => {
          "investor" => { "wif" => "cTpBinvestorWIF", "public_key_hex" => "02#{"b" * 64}" }
        }
      }
    )

    expect(described_class.investor_wif_for(budget)).to eq("cTpBinvestorWIF")
  end

  it "raises a helpful error when legacy keys do not match escrow pubkeys" do
    budget.update!(
      investor_pubkey: "02#{"a" * 64}",
      recovery_package: { "party_signing" => {} }
    )
    bob.btc_account.update!(
      escrow_identity_wif: "cTpBother",
      escrow_identity_pubkey: "02#{"b" * 64}"
    )

    expect do
      described_class.investor_wif_for(budget)
    end.to raise_error(L1::SettlementSpendService::Error, /non allineata all'escrow/)
  end
end
