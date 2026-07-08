# frozen_string_literal: true

require "rails_helper"

RSpec.describe L1::DepositReserveService do
  let(:user) { create(:user, email: "alice@example.com") }
  let(:user_wallet) { instance_double(L1::UserWallet, receive_address: "bcrt1test") }
  let(:exchange) { instance_double(L1::ExchangeWallet, transfer_to!: "txid") }

  before do
    allow(L1::Bitcoind::Client).to receive(:new).and_return(instance_double(L1::Bitcoind::Client, available?: true))
    allow(L1::UserWallet).to receive(:for).with(user).and_return(user_wallet)
    allow(user_wallet).to receive(:sync_balance_to_account!) do
      user.btc_account.update!(balance_sats: 10_000_000)
    end
    allow(L1::ExchangeWallet).to receive(:new).and_return(exchange)
    allow(ChainState).to receive(:block_height).and_return(800_000)
    allow(ChainState).to receive(:update_block_height!)
    user.btc_account.update!(balance_sats: 0)
  end

  it "transfers from exchange, syncs wallet balance and advances chain by 6 blocks" do
    result = described_class.call(user: user, amount_sats: 10_000_000)

    expect(exchange).to have_received(:transfer_to!).with(address: "bcrt1test", amount_sats: 10_000_000)
    expect(user_wallet).to have_received(:sync_balance_to_account!)
    expect(ChainState).to have_received(:update_block_height!).with(800_006)
    expect(result.balance_sats).to eq(10_000_000)
  end

  it "returns demo defaults per user" do
    expect(described_class.default_btc_amount_for(user)).to eq(0.02)
    expect(described_class.default_btc_amount_for(create(:user, email: "bob@example.com"))).to eq(0.2)
  end
end
