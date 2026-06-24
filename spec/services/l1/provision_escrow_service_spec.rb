# frozen_string_literal: true

require "rails_helper"

RSpec.describe L1::ProvisionEscrowService do
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }
  let(:budget) do
    setup_active_budget!(borrower: alice, investor: bob, amount_eur_cents: 100_000, peg: 50_000)
  end

  it "raises when bitcoind is unavailable" do
    unprovisioned = budget
    unprovisioned.update!(
      peg_party_pubkey: nil,
      investor_pubkey: nil,
      bot_pubkey: nil,
      escrow_txid: nil,
      escrow_vout: nil,
      recovery_package: nil
    )

    unavailable = instance_double(L1::Bitcoind::Client, available?: false)
    allow(L1::Bitcoind::Client).to receive(:new).and_return(unavailable)
    allow(L1::ProvisionEscrowService).to receive(:call).and_call_original

    expect do
      described_class.call(budget: unprovisioned)
    end.to raise_error(L1::ProvisionEscrowService::Error, /bitcoind regtest/)
  end

  it "skips when already provisioned" do
    budget.update!(
      peg_party_pubkey: "02#{"a" * 64}",
      investor_pubkey: "02#{"b" * 64}",
      bot_pubkey: "02#{"c" * 64}",
      escrow_txid: "abc",
      escrow_vout: 0,
      recovery_package: { "version" => 1 }
    )

    expect(L1::FundingPsbtService).not_to receive(:call)
    described_class.call(budget: budget)
  end
end
