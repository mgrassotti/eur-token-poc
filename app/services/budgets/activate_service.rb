# frozen_string_literal: true

module Budgets
  class ActivateService
    class Error < StandardError; end

    def self.call(budget:, investor:)
      new(budget:, investor:).call
    end

    def initialize(budget:, investor:)
      @budget = budget
      @investor = investor
    end

    def call
      validate!

      peg_eur_per_btc = MarketRate.current.btc_eur_per_btc

      ActiveRecord::Base.transaction do
        investor.btc_account.lock!
        L1::SyncReserveBalanceService.call(user: investor)

        collateral_sats = ReserveRequirement.investor_collateral_sats_for(budget, peg_eur_per_btc)
        required_sats = ReserveRequirement.investor_sats_for(budget, peg_eur_per_btc)
        available_sats = ReserveRequirement.available_sats_for(investor)

        if available_sats < required_sats
          raise Error,
                ReserveRequirement.insufficient_message(
                  label: "l'investitore",
                  required_sats: required_sats,
                  available_sats: available_sats,
                  eur_per_btc: peg_eur_per_btc
                )
        end

        total_locked_sats = collateral_sats + budget.borrower_locked_sats

        genesis_height = ChainState.block_height
        maturity_height = genesis_height + budget.symbolic_months_duration * Budget::BLOCKS_PER_MONTH

        budget.update!(
          investor: investor,
          investor_locked_sats: collateral_sats,
          peg_eur_per_btc: peg_eur_per_btc,
          genesis_block_height: genesis_height,
          maturity_block_height: maturity_height,
          status: :active
        )

        CollateralLock.create!(
          budget: budget,
          amount_sats: total_locked_sats,
          locked_at: Time.current
        )

        TokenAccount.create!(
          user: budget.borrower,
          budget: budget,
          balance_cents: budget.amount_eur_cents
        )
      end

      budget.reload
      L1::ProvisionEscrowService.call(budget: budget)
      budget.reload
    end

    private

    attr_reader :budget, :investor

    def validate!
      raise Error, "Budget is not pending" unless budget.pending?
      raise Error, "L'investitore non può essere il richiedente" if investor.id == budget.borrower_id
      raise Error, "L'admin deve impostare il cambio BTC/€ corrente" unless MarketRate.current.set?

      return if L1::Bitcoind::Client.new.available?

      raise Error, "bitcoind regtest non raggiungibile. Avvia: ./bin/regtest up"
    end
  end
end
