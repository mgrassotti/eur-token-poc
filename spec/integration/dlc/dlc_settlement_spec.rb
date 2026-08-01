# frozen_string_literal: true

require "rails_helper"

# End-to-end DLC settlement on regtest against the real stack (compose profile
# `dlc`): the Pythia oracle (Dlc::Config.oracle_url) + the rust-dlc node sidecar
# (Dlc::Config.node_url), on top of the demo RGB/L1 provisioning. Bring it up:
#   ./bin/regtest up
#   docker compose -f docker-compose.regtest.yml --profile dlc up -d
# The spec self-skips if any component is unreachable.
#
# ActivateService funds a 2-of-2 numeric DLC on the node (the 2-of-2 collateral
# lock is provisioned alongside it) and settlement runs the oracle-attested CET +
# peg_pot distribution.
RSpec.describe "DLC settlement (regtest)", :regtest, :dlc_integration do
  def bitcoind_available?
    L1::Bitcoind::Client.new.available?
  end

  before do
    skip "Avvia bitcoind regtest: ./bin/regtest up" unless bitcoind_available?
    skip "Oracle DLC non raggiungibile (#{Dlc::Config.oracle_url})" unless Dlc::Config.oracle_client.available?
    skip "Nodo DLC non raggiungibile (#{Dlc::Config.node_url})" unless Dlc::NodeClient.default.available?
    reset_demo_with_regtest!
  end

  it "announces, funds, executes the CET and distributes the peg_pot" do
    alice = demo_user(:alice)
    bob = demo_user(:bob)
    admin = demo_user(:admin)

    MarketRate.current.update!(btc_eur_per_btc: DemoFlowHelpers::PEG_EUR_PER_BTC, set_by: admin)

    # Phase 2: Set up reserve addresses and fund them
    alice_wallet = L1::UserWallet.for(alice)
    bob_wallet = L1::UserWallet.for(bob)
    alice.btc_account.update!(reserve_receive_address: alice_wallet.receive_address)
    bob.btc_account.update!(reserve_receive_address: bob_wallet.receive_address)

    L1::FundReceiveAddressService.call(
      address: alice.btc_account.reserve_receive_address,
      amount_sats: DemoFlowHelpers::ALICE_DEPOSIT_SATS
    )
    L1::FundReceiveAddressService.call(
      address: bob.btc_account.reserve_receive_address,
      amount_sats: DemoFlowHelpers::BOB_DEPOSIT_SATS
    )

    budget = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: DemoFlowHelpers::BUDGET_EUR_CENTS,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 2, 1)
    )

    # Activation funds the DLC on the node (oracle announcement + 2-of-2 funding tx).
    Budgets::ActivateService.call(budget: budget, investor: bob)
    budget.reload

    expect(budget.dlc_contract).to be_present
    expect(budget.dlc_contract).to be_funded
    expect(budget.dlc_contract.funding_txid).to be_present

    # Price rises before maturity; auto-settlement runs the DLC path.
    MarketRate.current.update!(btc_eur_per_btc: DemoFlowHelpers::SETTLEMENT_EUR_PER_BTC, set_by: admin)
    ChainState.update_block_height!(budget.maturity_block_height, auto_settle: true)
    budget.reload

    expect(budget).to be_settled
    expect(budget.dlc_settlement).to be_executed
    expect(budget.dlc_settlement.cet_txid).to be_present
    expect(budget.recovery_package.dig("dlc", "cet", "txid")).to be_present
    expect(budget.recovery_package.dig("dlc_distribution", "txid")).to be_present
  end
end
