# frozen_string_literal: true

module DemoFlowHelpers
  DEMO_EMAILS = {
    alice: "alice@example.com",
    bob: "bob@example.com",
    claude: "claude@example.com",
    david: "david@example.com",
    admin: "admin@example.com"
  }.freeze

  # Alice deposits slightly more than the 0.02 BTC collateral so the DLC funding
  # tx (funded from her reserve in Fase 1) has headroom for her share of the
  # on-chain funding fee; the remainder returns to her reserve as change.
  ALICE_DEPOSIT_SATS = 2_100_000   # 0.021 BTC (0.02 collateral + fee headroom)
  BOB_DEPOSIT_SATS = 10_000_000    # 0.1 BTC
  BUDGET_EUR_CENTS = 100_000       # 1_000 €
  PEG_EUR_PER_BTC = 50_000
  SETTLEMENT_EUR_PER_BTC = 55_000

  def demo_user(role)
    User.find_by!(email: DEMO_EMAILS.fetch(role))
  end

  def reset_demo_with_regtest!
    DemoData::ResetService.call
  end

  def reserve_sats(user)
    user.btc_account.reload.balance_sats
  end

  def reserve_eur(user, rate = MarketRate.current.btc_eur_per_btc)
    BtcConversion.sats_to_eur(reserve_sats(user), rate)
  end

  def investment_sats(user)
    user.invested_budgets.active.sum(:investor_locked_sats)
  end

  def investment_eur(user, rate = MarketRate.current.btc_eur_per_btc)
    BtcConversion.sats_to_eur(investment_sats(user), rate)
  end

  def spending_cents(user)
    Tokens::Spendable.total_cents_for(user)
  end

  def investable_budgets_for(user)
    Budget.awaiting_investor.order(:created_at).reject { |b| b.borrower_id == user.id }
  end

  def expect_reserve_sats!(user, expected_sats)
    expect(reserve_sats(user)).to eq(expected_sats)
  end

  def expect_reserve_eur!(user, expected_eur, rate: MarketRate.current.btc_eur_per_btc, tolerance: 0.02)
    expect(reserve_eur(user, rate)).to be_within(tolerance).of(expected_eur)
  end

  def expect_investment_eur!(user, expected_eur, rate: MarketRate.current.btc_eur_per_btc, tolerance: 0.02)
    expect(investment_eur(user, rate)).to be_within(tolerance).of(expected_eur)
  end

  def expect_spending_eur!(user, expected_eur, tolerance: 0.001)
    expect(spending_cents(user) / 100.0).to be_within(tolerance).of(expected_eur)
  end

  # Fase 1: the investor collateral is locked by spending Bob's reserve UTXOs into
  # the DLC funding tx; the remainder (minus his share of the on-chain funding
  # fee) returns to his reserve as change. The exact fee is computed by rust-dlc,
  # so callers assert within a small tolerance of this fee-free upper bound.
  def expected_bob_reserve_after_funding
    investor_locked = BtcConversion.eur_cents_to_sats(DemoFlowHelpers::BUDGET_EUR_CENTS, DemoFlowHelpers::PEG_EUR_PER_BTC)
    DemoFlowHelpers::BOB_DEPOSIT_SATS - investor_locked
  end

  # Investor collateral returned to reserve by the CET (accept-side output).
  def dlc_investor_return_sats(budget)
    budget.reload.recovery_package&.dig("dlc_distribution", "investor_payout_sats").to_i
  end

  # Actual per-holder payout recorded by Dlc::Distribution (sats), keyed by user.
  # Settlement pays exact FloorEUR targets from the combined CET outputs.
  def dlc_distribution_payouts_sats(budget)
    payouts = budget.reload.recovery_package&.dig("dlc_distribution", "payouts") || []
    payouts.each_with_object({}) { |p, acc| acc[p["user_id"]] = p["sats"] }
  end

  def dlc_peg_pot_sats(budget)
    budget.reload.recovery_package&.dig("dlc_distribution", "peg_pot_sats").to_i
  end

  def expected_settlement_payoff(budget, end_rate: DemoFlowHelpers::SETTLEMENT_EUR_PER_BTC)
    token_accounts = budget.token_accounts.where("balance_cents > 0").order(:id).to_a
    Payoffs::FloorEurCalculator.call(
      notional_eur_cents: budget.notional_eur_cents,
      notional_total_cents: budget.amount_eur_cents,
      holder_shares_cents: token_accounts.map(&:balance_cents),
      spot_eur_per_btc: end_rate,
      rate_bps_monthly: budget.rate_bps_monthly,
      months_elapsed: budget.months_elapsed(at_height: budget.maturity_block_height),
      escrow_total_sats: budget.pool_sats
    )
  end
end

RSpec.configure do |config|
  config.include DemoFlowHelpers
end
