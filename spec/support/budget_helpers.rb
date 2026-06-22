# frozen_string_literal: true

module BudgetHelpers
  def setup_active_budget!(borrower:, investor:, amount_eur_cents: 100_000, peg: 60_000, block_height: 0)
    ChainState.update_block_height!(block_height, auto_settle: false)
    MarketRate.current.update!(btc_eur_per_btc: peg)
    borrower.btc_account.update!(balance_sats: 10_000_000)
    investor.btc_account.update!(balance_sats: 10_000_000)
    budget = Budgets::CreateService.call(
      borrower: borrower,
      amount_eur_cents: amount_eur_cents,
      period_start: Date.current,
      period_end: Date.current + 6.months
    )
    Budgets::ActivateService.call(budget: budget, investor: investor)
    budget.reload
  end

  def advance_to_maturity!(budget, auto_settle: false)
    ChainState.update_block_height!(budget.maturity_block_height, auto_settle: auto_settle)
  end
end

RSpec.configure do |config|
  config.include BudgetHelpers
end
