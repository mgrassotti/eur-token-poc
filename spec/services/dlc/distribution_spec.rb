# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dlc::Distribution do
  let(:alice) { create(:user, name: "Alice") }
  let(:claude) { create(:user, name: "Claude") }
  let(:david) { create(:user, name: "David") }

  let(:budget) do
    create(:budget, amount_eur_cents: 100_000, collateral_eur_cents: 100_000, borrower: alice)
  end

  let!(:dlc_contract) do
    DlcContract.create!(
      budget: budget, oracle_event_id: "deal-#{budget.id}", ddk_contract_id: "c-1",
      funding_txid: "ab" * 32, funding_vout: 0, status: :executed, num_digits: 20
    )
  end

  let(:node) { instance_double(Dlc::NodeClient) }
  let(:resolver) { ->(user) { "addr-#{user.id}" } }

  before do
    TokenAccount.create!(budget: budget, user: alice, balance_cents: 50_000)
    TokenAccount.create!(budget: budget, user: claude, balance_cents: 30_000)
    TokenAccount.create!(budget: budget, user: david, balance_cents: 20_000)

    allow(node).to receive(:distribute).and_return(
      Dlc::NodeClient::DistributionResult.new(txid: "cd" * 32, payouts: [], raw: {})
    )
  end

  it "splits the peg_pot pro-rata on token balances and conserves the total" do
    payouts = described_class.call(
      budget: budget, peg_pot_sats: 1_000_000, node: node, address_resolver: resolver
    )

    by_user = payouts.to_h { |p| [p.user, p.sats] }
    expect(by_user[alice]).to eq(500_000)
    expect(by_user[claude]).to eq(300_000)
    expect(by_user[david]).to eq(200_000)
    expect(payouts.sum(&:sats)).to eq(1_000_000)
  end

  it "gives the rounding remainder to the last holder" do
    payouts = described_class.call(
      budget: budget, peg_pot_sats: 1_000_001, node: node, address_resolver: resolver
    )

    expect(payouts.sum(&:sats)).to eq(1_000_001)
    expect(payouts.last.user).to eq(david)
    expect(payouts.last.sats).to eq(200_001)
  end

  it "sends one on-chain payout with resolved holder addresses" do
    described_class.call(budget: budget, peg_pot_sats: 1_000_000, node: node, address_resolver: resolver)

    expect(node).to have_received(:distribute).with(
      contract_id: "c-1",
      payouts: [
        { address: "addr-#{alice.id}", sats: 500_000 },
        { address: "addr-#{claude.id}", sats: 300_000 },
        { address: "addr-#{david.id}", sats: 200_000 }
      ]
    )
  end

  it "records the distribution in the recovery package" do
    described_class.call(budget: budget, peg_pot_sats: 1_000_000, node: node, address_resolver: resolver)

    distribution = budget.reload.recovery_package["dlc_distribution"]
    expect(distribution["txid"]).to eq("cd" * 32)
    expect(distribution["peg_pot_sats"]).to eq(1_000_000)
    expect(distribution["payouts"].sum { |p| p["sats"] }).to eq(1_000_000)
  end

  it "wraps node failures in a distribution error" do
    allow(node).to receive(:distribute).and_raise(Dlc::NodeClient::Error, "broadcast failed")

    expect do
      described_class.call(budget: budget, peg_pot_sats: 1_000_000, node: node, address_resolver: resolver)
    end.to raise_error(described_class::Error, /Distribuzione DLC fallita: broadcast failed/)
  end

  it "raises when the budget has no DLC contract" do
    budget.dlc_contract.destroy!

    expect do
      described_class.call(budget: budget.reload, peg_pot_sats: 1_000_000, node: node, address_resolver: resolver)
    end.to raise_error(described_class::Error, /Nessun contratto DLC/)
  end
end
