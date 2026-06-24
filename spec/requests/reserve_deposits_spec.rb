# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReserveDepositsController, type: :request do
  let(:alice) { create(:user, name: "Alice", email: "alice@example.com") }

  def log_in(user)
    post session_path, params: { email: user.email, password: "password" }
  end

  it "shows the deposit form with Alice default" do
    log_in(alice)

    get new_reserve_deposit_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("0.1")
    expect(response.body).to include("Wallet esterno")
  end

  it "creates a reserve deposit with custom amount" do
    log_in(alice)
    allow(L1::DepositReserveService).to receive(:call).and_return(alice.btc_account.tap { |a| a.update!(balance_sats: 20_000_000) })

    post reserve_deposit_path, params: { amount_btc: "0.2" }

    expect(L1::DepositReserveService).to have_received(:call).with(user: alice, amount_sats: 20_000_000)
    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to include("Wallet esterno")
  end
end
