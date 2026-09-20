# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dlc::Watchtower do
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }

  let(:budget) do
    b = create(:budget, borrower: alice, investor: bob, status: :active, maturity_block_height: 10)
    DlcContract.create!(
      budget: b,
      oracle_event_id: "deal-#{b.id}",
      oracle_announcement: "{}",
      ddk_contract_id: "c-watch",
      funding_txid: "ab" * 32,
      funding_vout: 0,
      status: :funded,
      sign_package: { "refund_lock_time" => 20 },
      offerer_adaptor_sigs: %w[aa],
      acceptor_adaptor_sigs: %w[bb],
      offerer_refund_sig: "r1",
      acceptor_refund_sig: "r2"
    )
    b
  end

  it "broadcasts a pre-signed refund when the locktime height is reached" do
    budget
    ChainState.update_block_height!(budget.refund_locktime_height, auto_settle: false)
    node = instance_double(Dlc::NodeClient)
    allow(Dlc::NodeClient).to receive(:default).and_return(node)
    allow(node).to receive(:refund_contract).and_return(
      Dlc::NodeClient::Refund.new(refund_txid: "ef" * 32, raw: {})
    )

    refunded = described_class.refund_overdue

    expect(refunded.size).to eq(1)
    expect(budget.dlc_contract.reload).to be_refunded
    expect(node).to have_received(:refund_contract).with(
      contract_id: "c-watch",
      close_package: hash_including("offerer_refund_sig" => "r1")
    )
  end

  it "executes the attested CET from the close package once maturity is reached" do
    budget.update!(
      escrow_txid: "ab" * 32,
      escrow_vout: 0,
      peg_party_pubkey: "02#{"a" * 64}",
      investor_pubkey: "02#{"b" * 64}",
      genesis_block_height: 0,
      maturity_block_height: 10
    )
    MarketRate.current.update!(btc_eur_per_btc: 50_000)
    ChainState.update_block_height!(budget.maturity_block_height, auto_settle: false)
    allow(Dlc::SettlementService).to receive(:call).and_return(
      Dlc::SettlementService::Result.new(
        dlc_settlement: nil,
        cet_txid: "cd" * 32,
        outcome: 50_000,
        peg_pot_sats: 1,
        investor_sats: 1
      )
    )

    executed = described_class.execute_mature

    expect(executed.size).to eq(1)
    expect(Dlc::SettlementService).to have_received(:call).with(
      budget: budget,
      end_btc_eur_rate: 50_000
    )
  end

  it "does nothing before refund locktime" do
    budget
    ChainState.update_block_height!(budget.maturity_block_height, auto_settle: false)
    allow(Dlc::NodeClient).to receive(:default)

    expect(described_class.refund_overdue).to be_empty
    expect(Dlc::NodeClient).not_to have_received(:default)
  end
end
