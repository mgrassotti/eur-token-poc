# frozen_string_literal: true

require "rails_helper"

# Flusso demo via browser (regtest + RGB sidecar reale): bin/system-spec
RSpec.describe "Demo end-to-end flow (system)", type: :system, regtest: true, demo_flow: true,
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
    bob_reserve_before_settlement = reserve_sats(demo_user(:bob))
    payoff = expected_settlement_payoff(budget)

    advance_chain_to_maturity!(budget)

    expect_reserve_eur!(demo_user(:alice), 505.0, rate: DemoFlowHelpers::SETTLEMENT_EUR_PER_BTC)
    expect_reserve_eur!(demo_user(:claude), 404.0, rate: DemoFlowHelpers::SETTLEMENT_EUR_PER_BTC)
    expect_reserve_eur!(demo_user(:david), 101.0, rate: DemoFlowHelpers::SETTLEMENT_EUR_PER_BTC)
    expect_reserve_sats!(demo_user(:bob), bob_reserve_before_settlement + payoff.investor_remainder_sats)

    switch_to(:alice)
    second_budget = create_spending_budget!(
      amount_eur: 500,
      period_start: period_start + 2.months,
      period_end: period_start + 3.months
    )

    switch_to(:bob)
    activate_budget!(second_budget)
  end

  it "attiva un deal via UI (debug sidecar RGB su activate)" do
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
