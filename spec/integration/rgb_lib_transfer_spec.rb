# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RGB transfer via RGB Lightning Node", :l1_integration, :rgb_lib, :regtest do
  let(:strike) { 50_000 }
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:claude) { create(:user, name: "Claude") }

  it "issues RGB20 on activate and supports partial transfer across nodes" do
    assign_rln_nodes!(alice, bob, claude)

    # Phase 2: Set up reserve addresses and fund them
    alice_wallet = L1::UserWallet.for(alice)
    bob_wallet = L1::UserWallet.for(bob)
    alice.btc_account.update!(reserve_receive_address: alice_wallet.receive_address)
    bob.btc_account.update!(reserve_receive_address: bob_wallet.receive_address)

    # Add 10,000 sats funding fee buffer required by Budgets::CreateService
    L1::FundReceiveAddressService.call(
      address: alice.btc_account.reserve_receive_address,
      amount_sats: 25_010_000
    )
    L1::FundReceiveAddressService.call(
      address: bob.btc_account.reserve_receive_address,
      amount_sats: 25_010_000
    )

    MarketRate.current.update!(btc_eur_per_btc: strike)
    period_start = Date.new(2026, 1, 1)

    budget = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: 500_000,
      period_start: period_start,
      period_end: period_start >> 6
    )
    Budgets::ActivateService.call(budget: budget, investor: bob)
    budget.reload

    expect(budget.rgb_asset_id).to be_present
    asset_id = budget.rgb_asset_id
    expect(rln_settled(alice, asset_id)).to eq(500_000)

    transfer_amount = 200_000
    Tokens::TransferService.call(
      budget: budget,
      from_user: alice,
      to_user: claude,
      amount_cents: transfer_amount
    )

    # LibTransferService confirms on regtest, so balances are already settled.
    expect(rln_settled(alice, asset_id)).to eq(500_000 - transfer_amount)
    expect(rln_settled(claude, asset_id)).to eq(transfer_amount)

    expect(alice.rgb_assignments.find_by(budget: budget).notional_share_cents).to eq(500_000 - transfer_amount)
    expect(claude.rgb_assignments.find_by(budget: budget).notional_share_cents).to eq(transfer_amount)
  end
end
