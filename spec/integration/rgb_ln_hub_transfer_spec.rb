# frozen_string_literal: true

require "rails_helper"

# Alice → hub → Claude RGB-LN payment (no /sendrgb for the payment itself).
# Requires ./bin/regtest up. Hub = issuer RLN on :3005.
RSpec.describe "RGB-LN hub transfer", :l1_integration, :rgb_lib, :regtest do
  let(:strike) { 50_000 }
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:claude) { create(:user, name: "Claude") }

  around do |example|
    previous = ENV["RGB_TRANSFER_VIA_LN"]
    ENV["RGB_TRANSFER_VIA_LN"] = "1"
    example.run
  ensure
    if previous.nil?
      ENV.delete("RGB_TRANSFER_VIA_LN")
    else
      ENV["RGB_TRANSFER_VIA_LN"] = previous
    end
  end

  it "moves EURT Alice→Claude via hub LN without sendrgb for the payment" do
    assign_rln_nodes!(alice, bob, claude)

    L1::DepositReserveService.call(user: alice, amount_sats: 25_000_000)
    L1::DepositReserveService.call(user: bob, amount_sats: 25_000_000)

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

    asset_id = budget.rgb_asset_id
    expect(asset_id).to be_present
    expect(rln_settled(alice, asset_id)).to eq(500_000)

    # First send needs ~2× amount off-channel (hub seed + Alice channel). See spike notes.
    transfer_amount = 100_000

    allow(Rgb::LightningClient).to receive(:new).and_call_original
    sendrgb_calls = []
    sendpayment_calls = []
    allow_any_instance_of(Rgb::LightningClient).to receive(:send_asset).and_wrap_original do |method, **kwargs|
      sendrgb_calls << kwargs
      method.call(**kwargs)
    end
    allow_any_instance_of(Rgb::LightningClient).to receive(:send_payment).and_wrap_original do |method, **kwargs|
      sendpayment_calls << kwargs
      method.call(**kwargs)
    end

    Tokens::TransferService.call(
      budget: budget,
      from_user: alice,
      to_user: claude,
      amount_cents: transfer_amount
    )

    # Hub seeding may use /sendrgb once; the payment itself must be LN.
    expect(sendpayment_calls.size).to eq(1)
    expect(sendrgb_calls.size).to be <= 1

    alice_bal = Rgb::Nodes.for_user(alice).asset_balance(asset_id: asset_id)
    claude_bal = Rgb::Nodes.for_user(claude).asset_balance(asset_id: asset_id)

    alice_total = alice_bal["settled"].to_i + alice_bal["offchain_outbound"].to_i
    claude_total = claude_bal["settled"].to_i + claude_bal["offchain_outbound"].to_i

    # First send of X seeds hub with 2X and locks 2X into Alice→hub so a second
    # send of X needs no further L1. Alice node total drops by 4X on first setup
    # payment of X (2X seed + 2X channel, then −X payment from channel). Net −3X
    # after first payment; Claude +X. See spike notes.
    expect(alice_total).to eq(500_000 - (3 * transfer_amount))
    expect(claude_total).to eq(transfer_amount)

    expect(alice.rgb_assignments.find_by(budget: budget).notional_share_cents).to eq(500_000 - (3 * transfer_amount))
    expect(claude.rgb_assignments.find_by(budget: budget).notional_share_cents).to eq(transfer_amount)

    # Second transfer: capacity already open — no additional sendrgb.
    sendrgb_before = sendrgb_calls.size
    sendpayment_before = sendpayment_calls.size
    Tokens::TransferService.call(
      budget: budget,
      from_user: alice,
      to_user: claude,
      amount_cents: transfer_amount
    )
    expect(sendrgb_calls.size).to eq(sendrgb_before)
    expect(sendpayment_calls.size).to eq(sendpayment_before + 1)

    alice_bal = Rgb::Nodes.for_user(alice).asset_balance(asset_id: asset_id)
    claude_bal = Rgb::Nodes.for_user(claude).asset_balance(asset_id: asset_id)
    alice_total = alice_bal["settled"].to_i + alice_bal["offchain_outbound"].to_i
    claude_total = claude_bal["settled"].to_i + claude_bal["offchain_outbound"].to_i
    expect(alice_total).to eq(500_000 - (4 * transfer_amount))
    expect(claude_total).to eq(2 * transfer_amount)
  end
end
