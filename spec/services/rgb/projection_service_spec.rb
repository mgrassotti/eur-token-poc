# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rgb::ProjectionService do
  let(:alice) { create(:user) }
  let(:claude) { create(:user) }
  let(:budget) do
    create(:budget, borrower: alice, amount_eur_cents: 100_000, rgb_asset_id: "rgb_stub").tap do |record|
      TokenAccount.create!(user: alice, budget: record, balance_cents: 100_000)
      RgbAssignment.create!(
        budget: record,
        user: alice,
        assignment_id: SecureRandom.uuid,
        holder_pubkey: "02#{"a" * 64}",
        notional_share_cents: 100_000,
        rgb_asset_id: "rgb_stub"
      )
    end
  end

  let(:rgb_result) do
    Rgb::TransferResult.new(
      txid: "deadbeef",
      recipient_id: "rcp1",
      asset_id: "rgb_stub",
      amount: 25_000
    )
  end

  let(:issue_result) do
    Rgb::IssueResult.new(
      asset_id: "rgb_new",
      ticker: "E1",
      name: "FloorEUR deal 1",
      recipient_id: "rcp0",
      issue_txid: "cafebabe",
      amount_cents: 100_000
    )
  end

  describe ".apply_issue!" do
    let(:fresh_budget) { create(:budget, borrower: alice, amount_eur_cents: 100_000) }

    it "projects RGB issue into token account, assignment and recovery package" do
      assignment = described_class.apply_issue!(budget: fresh_budget, rgb_result: issue_result)

      fresh_budget.reload
      expect(fresh_budget.rgb_asset_id).to eq("rgb_new")
      expect(assignment.notional_share_cents).to eq(100_000)
      expect(alice.token_accounts.find_by!(budget: fresh_budget).balance_cents).to eq(100_000)
      expect(fresh_budget.recovery_package.dig("consignment_rgb", "issue_transfer_txid")).to eq("cafebabe")
    end
  end

  it "projects an RGB transfer into token accounts and rgb_assignments" do
    transfer = described_class.apply_transfer!(
      budget: budget,
      from_user: alice,
      to_user: claude,
      amount_cents: 25_000,
      rgb_result: rgb_result
    )

    expect(transfer.amount_cents).to eq(25_000)
    expect(alice.token_accounts.find_by!(budget: budget).balance_cents).to eq(75_000)
    expect(claude.token_accounts.find_by!(budget: budget).balance_cents).to eq(25_000)
    expect(alice.rgb_assignments.find_by!(budget: budget).notional_share_cents).to eq(75_000)
    expect(claude.rgb_assignments.find_by!(budget: budget).notional_share_cents).to eq(25_000)
  end

  it "zeroes the holder DB cache on redeem" do
    described_class.apply_redeem!(budget: budget, holder: alice)

    expect(alice.token_accounts.find_by!(budget: budget).balance_cents).to eq(0)
    expect(alice.rgb_assignments.find_by!(budget: budget).notional_share_cents).to eq(0)
  end
end
