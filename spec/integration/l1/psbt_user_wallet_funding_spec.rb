# frozen_string_literal: true

require "rails_helper"

# Fase 1: activation funds the DLC 2-of-2 straight from the borrower and
# investor L1 reserve wallets (no separate §3.2 PSBT escrow). Requires the live
# DLC stack (profile `dlc`) in addition to bitcoind.
RSpec.describe "L1 reserve-funded DLC collateral", :regtest, :dlc_integration do
  def bitcoind_available?
    L1::Bitcoind::Client.new.available?
  end

  before do
    skip "Start regtest: ./bin/regtest up" unless bitcoind_available?
    skip "Oracle DLC non raggiungibile (#{Dlc::Config.oracle_url})" unless Dlc::Config.oracle_client.available?
    skip "Nodo DLC non raggiungibile (#{Dlc::Config.node_url})" unless Dlc::NodeClient.default.available?
  end

  it "locks collateral via the DLC funding tx from borrower and investor reserves" do
    alice = create(:user, name: "Alice", email: "alice-reserve-#{SecureRandom.hex(4)}@example.com")
    bob = create(:user, name: "Bob", email: "bob-reserve-#{SecureRandom.hex(4)}@example.com")

    # Phase 2: Set up reserve addresses and fund them
    alice_wallet = L1::UserWallet.for(alice)
    bob_wallet = L1::UserWallet.for(bob)
    alice.btc_account.update!(reserve_receive_address: alice_wallet.receive_address)
    bob.btc_account.update!(reserve_receive_address: bob_wallet.receive_address)

    L1::FundReceiveAddressService.call(
      address: alice.btc_account.reserve_receive_address,
      amount_sats: 10_000_000
    )
    L1::FundReceiveAddressService.call(
      address: bob.btc_account.reserve_receive_address,
      amount_sats: 10_000_000
    )

    budget = setup_active_budget!(
      borrower: alice,
      investor: bob,
      amount_eur_cents: 100_000,
      peg: 50_000,
      block_height: 800_000
    )

    expect(budget.l1_multisig_provisioned?).to be(true)
    expect(budget.dlc_contract).to be_funded
    expect(budget.escrow_txid).to eq(budget.dlc_contract.funding_txid)
    expect(budget.recovery_package.dig("escrow", "outpoint")).to eq(budget.escrow_outpoint)
    expect(budget.recovery_package.dig("escrow", "note")).to include("Fase 1")
  end
end
