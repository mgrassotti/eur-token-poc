# frozen_string_literal: true

require "rails_helper"

# End-to-end DLC settlement on regtest. Requires a Kormir oracle and a ddk node
# (shim) reachable at Dlc::Config.oracle_url / node_url — these are NOT part of
# the default docker-compose stack yet, so the spec skips unless both answer.
# Wiring Kormir + ddk into docker-compose.regtest.yml is the remaining infra
# step (see DLC-RLN-PLAN.md). Run with: DLC_ENABLED=true bundle exec rspec
RSpec.describe "DLC settlement (regtest)", :regtest, :dlc_integration do
  before do
    skip "Avvia bitcoind regtest: ./bin/regtest up" unless L1::Bitcoind::Client.new.available?
    skip "Oracle DLC non raggiungibile (#{Dlc::Config.oracle_url})" unless Dlc::OracleClient.default.available?
    skip "Nodo DLC non raggiungibile (#{Dlc::Config.node_url})" unless Dlc::NodeClient.default.available?
  end

  it "announces, funds, executes the CET and distributes the peg_pot" do
    peg = 50_000
    alice = create(:user, name: "Alice")
    bob = create(:user, name: "Bob")
    alice.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(500_000, peg))
    bob.btc_account.update!(balance_sats: BtcConversion.eur_cents_to_sats(1_000_000, peg))
    MarketRate.current.update!(btc_eur_per_btc: peg)

    budget = Budgets::CreateService.call(
      borrower: alice, amount_eur_cents: 500_000,
      period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 7, 1)
    )

    allow(Dlc::Config).to receive(:enabled?).and_return(true)

    Budgets::ActivateService.call(budget: budget, investor: bob)
    budget.reload

    expect(budget.dlc_contract).to be_present
    expect(budget.dlc_contract).to be_funded

    advance_to_maturity!(budget)
    Settlements::ExecuteService.call(budget: budget, end_btc_eur_rate: 55_000)
    budget.reload

    expect(budget).to be_settled
    expect(budget.dlc_settlement).to be_executed
    expect(budget.recovery_package.dig("dlc", "cet", "txid")).to be_present
    expect(budget.recovery_package.dig("dlc_distribution", "txid")).to be_present
  end
end
