# frozen_string_literal: true

module Budgets
  # Builds FundingParams from bitcoind UserWallets (web PoC / regtest helpers).
  # Mobile clients supply UTXOs from BDK instead.
  class WalletFundingBuilder
    def self.call(budget:, investor:)
      new(budget:, investor:).call
    end

    def initialize(budget:, investor:)
      @budget = budget
      @investor = investor
    end

    def call
      peg_wallet = L1::UserWallet.for(budget.borrower)
      investor_wallet = L1::UserWallet.for(investor)
      buffer = Dlc::ContractSetupService::FUNDING_FEE_BUFFER_SATS

      peg_needed = ReserveRequirement.borrower_funding_required_sats_for(budget)
      investor_needed = budget.collateral_sats_at_peg(MarketRate.current.btc_eur_per_btc) + buffer

      FundingParams.new(
        peg_inputs: peg_wallet.select_coins(peg_needed).map { |c| coin_input(c) },
        investor_inputs: investor_wallet.select_coins(investor_needed).map { |c| coin_input(c) },
        peg_change_address: peg_wallet.change_address,
        investor_change_address: investor_wallet.change_address,
        investor_payout_address: investor_wallet.receive_address(label: "dlc_settlement"),
        peg_identity_pubkey: peg_wallet.identity_pubkey,
        investor_identity_pubkey: investor_wallet.identity_pubkey
      )
    end

    def wallets
      [L1::UserWallet.for(budget.borrower), L1::UserWallet.for(investor)]
    end

    private

    attr_reader :budget, :investor

    def coin_input(coin)
      {
        txid: coin.fetch("txid"),
        vout: coin.fetch("vout"),
        amount_sats: (coin.fetch("amount").to_d * 100_000_000).to_i
      }
    end
  end
end
