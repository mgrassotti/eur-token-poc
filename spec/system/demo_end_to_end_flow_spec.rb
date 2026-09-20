# frozen_string_literal: true

require "rails_helper"

# Flusso demo via browser (regtest + RGB Lightning Nodes reali): bin/system-spec
RSpec.describe "Demo end-to-end flow (system)", type: :system, regtest: true, demo_flow: true, skip: "MVP savings: RGB transfers removed from the happy path",
               use_transactional_fixtures: false do
  def bitcoind_available?
    L1::Bitcoind::Client.new.available?
  end

  before do
    skip "Start regtest: ./bin/regtest up" unless bitcoind_available?
    reset_demo_with_regtest!
  end

  it "percorre reset → depositi → deal → transfer → settlement via UI" do
    period_start = Date.new(2026, 1, 1)
    period_end = Date.new(2026, 2, 1)

    login_as(:admin)
    set_market_rate!(DemoFlowHelpers::PEG_EUR_PER_BTC)

    switch_to(:alice)
    deposit_reserve!(sats: DemoFlowHelpers::ALICE_DEPOSIT_SATS)
    expect_reserve_sats!(demo_user(:alice), DemoFlowHelpers::ALICE_DEPOSIT_SATS)

    switch_to(:bob)
    deposit_reserve!(sats: DemoFlowHelpers::BOB_DEPOSIT_SATS)
    expect_reserve_sats!(demo_user(:bob), DemoFlowHelpers::BOB_DEPOSIT_SATS)

    switch_to(:alice)
    budget = create_spending_budget!(
      amount_eur: DemoFlowHelpers::BUDGET_EUR_CENTS / 100.0,
      period_start: period_start,
      period_end: period_end
    )
    expect(budget).to be_pending

    switch_to(:bob)
    activate_budget!(budget)
    expect_spending_eur!(demo_user(:alice), 1_000.0)
    expect_rgb_card_visible!

    switch_to(:alice)
    send_tokens!(to_user: demo_user(:claude), amount_eur: 500)
    expect_spending_eur!(demo_user(:alice), 500.0)
    expect_spending_eur!(demo_user(:claude), 500.0)

    switch_to(:claude)
    send_tokens!(to_user: demo_user(:david), amount_eur: 100)
    expect_spending_eur!(demo_user(:claude), 400.0)
    expect_spending_eur!(demo_user(:david), 100.0)

    switch_to(:admin)
    set_market_rate!(DemoFlowHelpers::SETTLEMENT_EUR_PER_BTC)
    holders = [demo_user(:alice), demo_user(:claude), demo_user(:david)]
    reserve_before = (holders + [demo_user(:bob)]).to_h { |u| [u.id, reserve_sats(u)] }

    advance_chain_to_maturity!(budget)

    # Settlement DLC (Fase 1): la CET rilascia il peg_pot reale sul lato peg,
    # distribuito pro-rata agli holder sulla riserva L1; l'output investitore della
    # CET torna direttamente sulla riserva di Bob. Ogni riserva cresce del delta.
    budget.reload
    distribution = dlc_distribution_payouts_sats(budget)
    holders.each do |user|
      expect(reserve_sats(user)).to eq(reserve_before.fetch(user.id) + distribution.fetch(user.id))
    end
    expect(reserve_sats(demo_user(:bob))).to eq(reserve_before.fetch(demo_user(:bob).id) + dlc_investor_return_sats(budget))

    switch_to(:alice)
    second_budget = create_spending_budget!(
      amount_eur: 500,
      period_start: period_start + 2.months,
      period_end: period_start + 3.months
    )

    switch_to(:bob)
    activate_budget!(second_budget)
  end

  it "attiva un deal via UI (debug RGB Lightning Node su activate)" do
    period_start = Date.new(2026, 1, 1)
    period_end = Date.new(2026, 2, 1)

    login_as(:admin)
    set_market_rate!(DemoFlowHelpers::PEG_EUR_PER_BTC)

    switch_to(:alice)
    deposit_reserve!(sats: DemoFlowHelpers::ALICE_DEPOSIT_SATS)

    switch_to(:bob)
    deposit_reserve!(sats: DemoFlowHelpers::BOB_DEPOSIT_SATS)

    switch_to(:alice)
    budget = create_spending_budget!(
      amount_eur: DemoFlowHelpers::BUDGET_EUR_CENTS / 100.0,
      period_start: period_start,
      period_end: period_end
    )

    switch_to(:bob)
    activate_budget!(budget)
    expect_rgb_card_visible!

    switch_to(:alice)
    expect(page).to have_content("€1000.00")
    expect_rgb_card_visible!
  end
end
