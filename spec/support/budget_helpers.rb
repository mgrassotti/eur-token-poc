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
    unit_activate_budget!(budget, investor: investor)
    budget.reload
  end

  def synthetic_funding_for(budget, peg: MarketRate.current.btc_eur_per_btc)
    collateral = budget.collateral_sats_at_peg(peg)
    buffer = Dlc::ContractSetupService::FUNDING_FEE_BUFFER_SATS
    Budgets::FundingParams.synthetic(
      peg_sats: budget.borrower_locked_sats + buffer,
      investor_sats: collateral + buffer
    )
  end

  def unit_activate_budget!(budget, investor:, verify_utxos: false, auto_sign_wallets: nil)
    Budgets::ActivateService.call(
      budget: budget,
      investor: investor,
      funding: synthetic_funding_for(budget),
      verify_utxos: verify_utxos,
      auto_sign_wallets: auto_sign_wallets
    )
  end

  # Real L1: select coins from bitcoind wallets and auto-sign funding.
  def activate_budget_with_wallets!(budget, investor:)
    builder = Budgets::WalletFundingBuilder.new(budget: budget, investor: investor)
    Budgets::ActivateService.call(
      budget: budget,
      investor: investor,
      funding: builder.call,
      verify_utxos: true,
      auto_sign_wallets: builder.wallets
    )
  end

  def advance_to_maturity!(budget, auto_settle: false)
    ChainState.update_block_height!(budget.maturity_block_height, auto_settle: auto_settle)
  end
end

RSpec.configure do |config|
  config.include BudgetHelpers
end
