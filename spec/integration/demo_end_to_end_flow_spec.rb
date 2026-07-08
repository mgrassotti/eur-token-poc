# frozen_string_literal: true

require "rails_helper"

# Flusso demo (regtest + RGB Lightning Nodes reali): eseguire con bin/demo-spec
RSpec.describe "Demo end-to-end flow", :regtest, :demo_flow do
  def bitcoind_available?
    L1::Bitcoind::Client.new.available?
  end

  before do
    skip "Start regtest: ./bin/regtest up" unless bitcoind_available?
    reset_demo_with_regtest!
  end

  it "percorre reset → depositi → deal → transfer → settlement automatico con saldi attesi" do
    alice = demo_user(:alice)
    bob = demo_user(:bob)
    claude = demo_user(:claude)
    david = demo_user(:david)
    admin = demo_user(:admin)

    MarketRate.current.update!(btc_eur_per_btc: DemoFlowHelpers::PEG_EUR_PER_BTC, set_by: admin)

    # Depositi on-chain
    L1::DepositReserveService.call(user: alice, amount_sats: DemoFlowHelpers::ALICE_DEPOSIT_SATS)
    L1::DepositReserveService.call(user: bob, amount_sats: DemoFlowHelpers::BOB_DEPOSIT_SATS)

    expect_reserve_sats!(alice, DemoFlowHelpers::ALICE_DEPOSIT_SATS)
    expect_reserve_sats!(bob, DemoFlowHelpers::BOB_DEPOSIT_SATS)

    # Alice richiede 1_000 € (usa tutto il collateral 0,02 BTC @ 50k)
    period_start = Date.new(2026, 1, 1)
    period_end = Date.new(2026, 2, 1) # 1 mese simbolico → 1% interesse a maturity

    budget = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: DemoFlowHelpers::BUDGET_EUR_CENTS,
      period_start: period_start,
      period_end: period_end
    )

    expect(budget).to be_pending
    expect(alice.borrowed_budgets.pending).to include(budget)
    expect(investable_budgets_for(bob).map(&:id)).to include(budget.id)

    # Bob accetta: escrow L1 + conti aggiornati
    Budgets::ActivateService.call(budget: budget, investor: bob)
    budget.reload

    expect(budget).to be_active
    expect(budget.l1_multisig_provisioned?).to be(true)

    # Fase 1: the DLC funding tx spends Bob's reserve; his change returns minus his
    # share of the rust-dlc funding fee (a few hundred sats at the default rate).
    expect(reserve_sats(bob)).to be_within(5_000).of(expected_bob_reserve_after_funding)
    expect_investment_eur!(bob, 1_000.0, rate: DemoFlowHelpers::PEG_EUR_PER_BTC)

    expect_spending_eur!(alice, 1_000.0)

    # Transfer EURT sul conto spesa
    Tokens::TransferService.call(budget: budget, from_user: alice, to_user: claude, amount_cents: 50_000)
    expect_spending_eur!(alice, 500.0)
    expect_spending_eur!(claude, 500.0)

    Tokens::TransferService.call(budget: budget, from_user: claude, to_user: david, amount_cents: 10_000)
    expect_spending_eur!(claude, 400.0)
    expect_spending_eur!(david, 100.0)
    expect_spending_eur!(alice, 500.0)

    # Prezzo sale a 55k €/BTC prima del settlement automatico
    MarketRate.current.update!(btc_eur_per_btc: DemoFlowHelpers::SETTLEMENT_EUR_PER_BTC, set_by: admin)

    payoff = expected_settlement_payoff(budget)
    expect(payoff.liability_eur_cents).to eq(101_000) # 1_000 € + 10 € interessi (1 mese @ 1%)

    # Riserve pre-settlement: gli holder (alice ha il resto del funding, claude e
    # david non hanno depositato) e l'investitore. In Fase 1 il settlement AGGIUNGE
    # alla riserva (collateral restituito), quindi si verifica il delta.
    reserve_before = [alice, claude, david, bob].to_h { |u| [u.id, reserve_sats(u)] }

    ChainState.update_block_height!(budget.maturity_block_height, auto_settle: true)

    budget.reload
    expect(budget).to be_settled
    expect(budget.dlc_settlement).to be_executed

    # Settlement DLC (Fase 1): la CET rilascia il peg_pot (reale) sul lato peg,
    # distribuito pro-rata agli holder sulle loro riserve L1 (Dlc::Distribution).
    # Ogni riserva holder cresce esattamente della distribuzione registrata.
    distribution = dlc_distribution_payouts_sats(budget)
    [alice, claude, david].each do |user|
      expect(reserve_sats(user)).to eq(reserve_before.fetch(user.id) + distribution.fetch(user.id))
    end
    expect(distribution.values.sum).to eq(dlc_peg_pot_sats(budget))
    expect(reserve_eur(alice, DemoFlowHelpers::SETTLEMENT_EUR_PER_BTC)).to be > 0

    # Investitore (Fase 1): la CET restituisce il collateral investitore
    # DIRETTAMENTE sulla riserva L1 di Bob (output accept della CET). Il lock è
    # rilasciato e la riserva cresce dell'output investitore della CET.
    expect(dlc_investor_return_sats(budget)).to be > 0
    expect(reserve_sats(bob)).to eq(reserve_before.fetch(bob.id) + dlc_investor_return_sats(budget))
    expect(investment_sats(bob)).to eq(0)

    # Alice riusa la riserva post-settlement per una nuova ricarica da 500 € (@ 55k)
    alice_reserve_sats = reserve_sats(alice)
    second_budget_eur_cents = 50_000
    required_sats = BtcConversion.eur_cents_to_sats(
      second_budget_eur_cents,
      DemoFlowHelpers::SETTLEMENT_EUR_PER_BTC
    )
    expect(alice_reserve_sats).to be >= required_sats

    second_budget = Budgets::CreateService.call(
      borrower: alice,
      amount_eur_cents: second_budget_eur_cents,
      period_start: period_start + 2.months,
      period_end: period_start + 3.months
    )
    expect(second_budget).to be_pending
    expect(second_budget.borrower_locked_sats).to eq(required_sats)

    Budgets::ActivateService.call(budget: second_budget, investor: bob)
    second_budget.reload

    expect(second_budget).to be_active
    expect(second_budget.l1_multisig_provisioned?).to be(true)
  end
end
