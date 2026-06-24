# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RGB lib transfer via sidecar", :l1_integration, :rgb_lib do
  let(:strike) { 50_000 }
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:claude) { create(:user, name: "Claude") }

  it "issues RGB20 on activate and supports partial transfer" do
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

    expect(budget.rgb_asset_id).to be_present
    expect(Rgb::SidecarClient.instance.list_assets(Rgb::Config.wallet_id_for(alice))["nia"]).not_to be_empty

    transfer_amount = 200_000
    Tokens::TransferService.call(
      budget: budget,
      from_user: alice,
      to_user: claude,
      amount_cents: transfer_amount
    )

    alice_assets = Rgb::SidecarClient.instance.list_assets(Rgb::Config.wallet_id_for(alice))["nia"]
    claude_assets = Rgb::SidecarClient.instance.list_assets(Rgb::Config.wallet_id_for(claude))["nia"]

    alice_balance = alice_assets.find { |a| a["asset_id"] == budget.rgb_asset_id }.fetch("balance").fetch("settled")
    claude_balance = claude_assets.find { |a| a["asset_id"] == budget.rgb_asset_id }.fetch("balance").fetch("settled")

    expect(alice_balance).to eq(500_000 - transfer_amount)
    expect(claude_balance).to eq(transfer_amount)
    expect(alice.rgb_assignments.find_by(budget: budget).notional_share_cents).to eq(500_000 - transfer_amount)
    expect(claude.rgb_assignments.find_by(budget: budget).notional_share_cents).to eq(transfer_amount)
  end
end
