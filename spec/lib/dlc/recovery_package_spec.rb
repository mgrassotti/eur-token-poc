# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dlc::RecoveryPackage do
  let(:budget) do
    create(
      :budget,
      amount_eur_cents: 500_000,
      collateral_eur_cents: 500_000,
      maturity_block_height: 1_000,
      refund_delay_blocks: 1_008
    )
  end

  let!(:dlc_contract) do
    DlcContract.create!(
      budget: budget, oracle_event_id: "deal-#{budget.id}", oracle_announcement: "annhex",
      ddk_contract_id: "c-1", funding_txid: "ab" * 32, funding_vout: 0, num_digits: 20,
      unit: "EUR/BTC", maturity_epoch: 1_790_000_000, peg_collateral_sats: 10_000_000,
      investor_collateral_sats: 10_000_000, status: :funded
    )
  end

  it "exports oracle, contract and refund coordinates before maturity" do
    package = described_class.build(budget: budget)

    expect(package[:version]).to eq(described_class::VERSION)
    expect(package[:oracle][:event_id]).to eq("deal-#{budget.id}")
    expect(package[:oracle][:announcement]).to eq("annhex")
    expect(package[:oracle][:attestation]).to be_nil
    expect(package[:contract][:funding_outpoint]).to eq("#{'ab' * 32}:0")
    expect(package[:cet][:note]).to match(/Non ancora eseguito/)
    expect(package[:refund][:locktime_height]).to eq(2_008)
  end

  it "includes the attestation and CET once settled" do
    DlcSettlement.create!(
      budget: budget, dlc_contract: dlc_contract, cet_txid: "cd" * 32, outcome: 55_000,
      attestation: "atthex", peg_pot_sats: 8_000_000, investor_sats: 12_000_000,
      status: :executed, executed_at: Time.current
    )

    package = described_class.build(budget: budget.reload)

    expect(package[:oracle][:attestation]).to eq("atthex")
    expect(package[:oracle][:outcome]).to eq(55_000)
    expect(package[:cet][:txid]).to eq("cd" * 32)
    expect(package[:cet][:peg_pot_sats]).to eq(8_000_000)
  end

  it "raises when the budget has no DLC contract" do
    budget.dlc_contract.destroy!

    expect { described_class.build(budget: budget.reload) }
      .to raise_error(ArgumentError, /senza contratto DLC/)
  end
end
