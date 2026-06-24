# frozen_string_literal: true

require "rails_helper"

RSpec.describe "L1 PSBT user-wallet funding", :regtest do
  def bitcoind_available?
    L1::Bitcoind::Client.new.available?
  end

  before do
    skip "Start regtest: docker compose -f docker-compose.regtest.yml up -d" unless bitcoind_available?
  end

  it "funds escrow via §3.2 PSBT from borrower and investor wallets" do
    alice = create(:user, name: "Alice", email: "alice-psbt-#{SecureRandom.hex(4)}@example.com")
    bob = create(:user, name: "Bob", email: "bob-psbt-#{SecureRandom.hex(4)}@example.com")

    L1::DepositReserveService.call(user: alice, amount_sats: 10_000_000)
    L1::DepositReserveService.call(user: bob, amount_sats: 10_000_000)

    budget = setup_active_budget!(
      borrower: alice,
      investor: bob,
      amount_eur_cents: 100_000,
      peg: 50_000,
      block_height: 800_000
    )

    expect(budget.l1_multisig_provisioned?).to be(true)
    expect(budget.recovery_package.dig("psbt_funding", "mode")).to eq("§3.2 async PSBT")
    expect(budget.recovery_package.dig("psbt_funding", "psbt")).to be_present
    expect(budget.escrow_txid).to be_present
  end
end
