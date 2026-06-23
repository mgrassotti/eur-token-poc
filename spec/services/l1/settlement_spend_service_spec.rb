# frozen_string_literal: true

require "rails_helper"

RSpec.describe L1::SettlementSpendService do
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }
  let(:budget) do
    setup_active_budget!(borrower: alice, investor: bob, amount_eur_cents: 100_000, peg: 50_000)
  end
  let(:payoff) do
    Payoffs::FloorEurCalculator.call(
      notional_eur_cents: budget.notional_eur_cents,
      notional_total_cents: budget.amount_eur_cents,
      holder_shares_cents: [100_000],
      spot_eur_per_btc: 50_000,
      rate_bps_monthly: budget.rate_bps_monthly,
      months_elapsed: budget.months_elapsed,
      escrow_total_sats: budget.pool_sats
    )
  end
  let(:holder_payouts) { [{ user: alice, btc_sats: payoff.holder_allocations.first.btc_sats }] }

  before do
    budget.update!(
      peg_party_pubkey: "02#{"a" * 64}",
      investor_pubkey: "02#{"b" * 64}",
      bot_pubkey: "02#{"c" * 64}",
      escrow_txid: "abc123",
      escrow_vout: 0,
      recovery_package: {
        "escrow" => {
          "address" => "bcrt1escrow",
          "redeem_script_hex" => "5221#{"aa" * 33}21#{"bb" * 33}21#{"cc" * 33}53ae",
          "amount_sats" => budget.pool_sats
        },
        "bot_signing" => { "wif" => "cTpBprivkeyWIFexample0000000000000000001" }
      }
    )
  end

  it "raises when escrow is not provisioned" do
    budget.update!(escrow_txid: nil, peg_party_pubkey: nil)

    expect do
      described_class.call(budget: budget, payoff: payoff, holder_payouts: holder_payouts)
    end.to raise_error(L1::SettlementSpendService::Error, /Escrow L1 non provisionato/)
  end

  it "raises when bot signing key is missing" do
    package = budget.recovery_package.deep_dup
    package["bot_signing"] = {}
    budget.update!(recovery_package: package)

    expect do
      described_class.call(budget: budget, payoff: payoff, holder_payouts: holder_payouts)
    end.to raise_error(L1::SettlementSpendService::Error, /Chiave bot mancante/)
  end
end
