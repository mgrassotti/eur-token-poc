# frozen_string_literal: true

require "rails_helper"

RSpec.describe L1::ProvisionEscrowService do
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }
  let(:budget) do
    previous = ENV["L1_ENABLED"]
    ENV["L1_ENABLED"] = "0"
    active = setup_active_budget!(borrower: alice, investor: bob, amount_eur_cents: 100_000, peg: 50_000)
    ENV["L1_ENABLED"] = previous
    active
  end

  after do
    ENV.delete("L1_ENABLED")
  end

  it "is a no-op when L1 is disabled" do
    ENV["L1_ENABLED"] = "0"

    expect(described_class.call(budget: budget)).to eq(budget)
    expect(budget.reload.l1_multisig_provisioned?).to be(false)
  end

  context "when L1 is enabled" do
    before { ENV["L1_ENABLED"] = "1" }

    it "raises when bitcoind is unavailable" do
      unavailable = instance_double(L1::Bitcoind::Client, available?: false)
      allow(L1::Bitcoind::Client).to receive(:new).and_return(unavailable)

      expect do
        described_class.call(budget: budget)
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
end
