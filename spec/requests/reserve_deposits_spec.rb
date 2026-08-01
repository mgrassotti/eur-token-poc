# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReserveDepositsController, type: :request do
  let(:alice) { create(:user, name: "Alice", email: "alice@example.com") }
  let(:test_address) { "bcrt1qtest" }

  def log_in(user)
    post session_path, params: { email: user.email, password: "password" }
  end

  it "shows the deposit form with stored address" do
    log_in(alice)
    # Phase 2: Address is stored in the database
    alice.btc_account.update!(reserve_receive_address: test_address)

    get new_reserve_deposit_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("0.1") # Default amount changed in Phase 2
    expect(response.body).to include("deposito")
  end

  it "creates a reserve deposit with custom amount" do
    log_in(alice)
    alice.btc_account.update!(reserve_receive_address: test_address)

    allow(L1::FundReceiveAddressService).to receive(:call).and_return(
      L1::FundReceiveAddressService::Result.new(
        txid: "test_txid",
        address: test_address,
        amount_sats: 20_000_000,
        btc_account: alice.btc_account.tap { |a| a.update!(balance_sats: 20_000_000) }
      )
    )

    post reserve_deposit_path, params: { amount_btc: "0.2" }

    expect(L1::FundReceiveAddressService).to have_received(:call).with(address: test_address, amount_sats: 20_000_000)
    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to include("Funded")
  end
end
