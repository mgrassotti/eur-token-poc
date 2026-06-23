# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetRecoveryPackagesController, type: :request do
  let(:alice) { create(:user, name: "Alice") }
  let(:bob) { create(:user, name: "Bob") }
  let(:claude) { create(:user, name: "Claude") }
  let(:admin) { create(:user, name: "Admin", admin: true) }
  let(:budget) do
    setup_active_budget!(borrower: alice, investor: bob, amount_eur_cents: 100_000, peg: 50_000)
  end
  let!(:recovery_package) do
    budget.update!(
      peg_party_pubkey: "02#{"a" * 64}",
      investor_pubkey: "02#{"b" * 64}",
      bot_pubkey: "02#{"c" * 64}",
      escrow_txid: "deadbeef",
      escrow_vout: 0,
      recovery_package: {
        "version" => 1,
        "deal_params" => { "deal_id" => budget.id },
        "escrow" => { "outpoint" => "deadbeef:0" }
      }
    )
    budget.recovery_package
  end

  def log_in(user)
    post session_path, params: { email: user.email, password: "password" }
  end

  it "lets the borrower download JSON" do
    log_in(alice)

    get budget_recovery_package_path(budget)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Content-Disposition"]).to include("recovery_package_budget_#{budget.id}.json")
    expect(JSON.parse(response.body)).to include("version" => 1)
  end

  it "lets the investor download JSON" do
    log_in(bob)

    get budget_recovery_package_path(budget)

    expect(response).to have_http_status(:ok)
  end

  it "forbids unrelated users" do
    log_in(claude)

    get budget_recovery_package_path(budget)

    expect(response).to redirect_to(root_path)
  end

  it "redirects when package is missing" do
    budget.update!(recovery_package: nil, escrow_txid: nil, peg_party_pubkey: nil)
    log_in(alice)

    get budget_recovery_package_path(budget)

    expect(response).to redirect_to(budget_path(budget))
  end
end
