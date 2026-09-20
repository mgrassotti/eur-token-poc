# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::SubmitDlcSignatureService do
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:saver_addr) { "bcrt1qsaver0000000000000000000000001" }
  let(:investor_addr) { "bcrt1qinvestor000000000000000000001" }

  let(:budget) do
    alice.btc_account.update!(reserve_receive_address: saver_addr)
    bob.btc_account.update!(reserve_receive_address: investor_addr)
    b = create(
      :budget,
      borrower: alice,
      investor: bob,
      status: :active,
      funding_address: saver_addr,
      borrower_change_address: saver_addr,
      investor_change_address: investor_addr,
      investor_payout_address: investor_addr,
      funding_psbt: "cHNidP2",
      borrower_funding_signed: true,
      investor_funding_signed: true
    )
    DlcContract.create!(
      budget: b,
      oracle_event_id: "deal-#{b.id}",
      oracle_announcement: "{}",
      ddk_contract_id: "c-1",
      funding_txid: "ab" * 32,
      funding_vout: 0,
      status: :announced,
      sign_package: { "cets" => ["00"], "base" => 2 }
    )
    b
  end

  before do
    allow(Dlc::NodeClient).to receive(:default).and_return(
      instance_double(Dlc::NodeClient, available?: false)
    )
    allow(Budgets::FinalizeFundingService).to receive(:call)
  end

  it "records saver adaptor signatures and does not finalize until both sides signed" do
    described_class.call(
      budget: budget,
      funding_address: saver_addr,
      adaptor_sigs: %w[aa bb],
      refund_sig: "cc"
    )

    expect(budget.reload.borrower_dlc_signed).to be(true)
    expect(budget.investor_dlc_signed).to be(false)
    expect(budget.dlc_contract.offerer_adaptor_sigs).to eq(%w[aa bb])
    expect(Budgets::FinalizeFundingService).not_to have_received(:call)
  end

  it "finalizes when the second party uploads CET signatures" do
    described_class.call(
      budget: budget,
      funding_address: saver_addr,
      adaptor_sigs: %w[aa],
      refund_sig: "r1"
    )
    described_class.call(
      budget: budget.reload,
      funding_address: investor_addr,
      adaptor_sigs: %w[dd],
      refund_sig: "r2"
    )

    expect(budget.reload.borrower_dlc_signed).to be(true)
    expect(budget.investor_dlc_signed).to be(true)
    expect(Budgets::FinalizeFundingService).to have_received(:call)
  end
end
