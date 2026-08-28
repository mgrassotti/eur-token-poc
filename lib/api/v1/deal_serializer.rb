# frozen_string_literal: true

module Api
  module V1
    class DealSerializer
      SCHEMA_VERSION = 1

      def self.render(deal, market_rate: MarketRate.current, detail: false)
        new(deal, market_rate:, detail:).as_json
      end

      def initialize(deal, market_rate:, detail:)
        @deal = deal
        @market_rate = market_rate
        @detail = detail
      end

      def as_json
        base = {
          schema_version: SCHEMA_VERSION,
          id: deal.id.to_s,
          status: deal.status,
          borrower: user_json(deal.borrower),
          investor: deal.investor ? user_json(deal.investor) : nil,
          amount_eur_cents: deal.amount_eur_cents,
          collateral_eur_cents: deal.collateral_eur_cents,
          rate_bps_monthly: deal.rate_bps_monthly,
          period: {
            start: deal.period_start.iso8601,
            end: deal.period_end.iso8601
          },
          peg_eur_per_btc: deal.peg_eur_per_btc&.to_f,
          pool_sats: deal.pool_sats,
          genesis_block_height: deal.genesis_block_height,
          maturity_block_height: deal.maturity_block_height,
          blocks_remaining: deal.blocks_remaining,
          ready_for_settlement: deal.ready_for_settlement?,
          funding_address: deal.funding_address,
          investor_funding_address: deal.investor&.btc_account&.reserve_receive_address.presence ||
                                    deal.investor_change_address,
          awaiting_funding_signatures: deal.funding_psbt.present? && !deal.l1_multisig_provisioned?,
          borrower_funding_signed: deal.borrower_funding_signed,
          investor_funding_signed: deal.investor_funding_signed,
          created_at: deal.created_at.iso8601,
          updated_at: deal.updated_at.iso8601
        }

        if market_rate.set?
          base[:ltv] = deal.loan_to_value_ratio(market_rate.btc_eur_per_btc)
          base[:provisional_peg_eur_per_btc] = deal.provisional_strike_eur_per_btc(market_rate: market_rate)&.to_f
        end

        return base unless detail

        base.merge(
          token_holders: token_holders,
          token_transfers_count: deal.token_transfers.count,
          liability_eur_cents: liability_preview,
          dlc_funded: deal.dlc_contract&.funded? || false,
          funding_psbt: deal.l1_multisig_provisioned? ? nil : deal.funding_psbt
        )
      end

      private

      attr_reader :deal, :market_rate, :detail

      def user_json(user)
        { id: user.id, name: user.name, email: user.email }
      end

      def token_holders
        deal.token_accounts.includes(:user).where("balance_cents > 0").order(:id).map do |account|
          {
            user: user_json(account.user),
            balance_cents: account.balance_cents,
            liability_eur_cents: deal.holder_liability_cents(account.balance_cents),
            interest_cents: deal.holder_interest_at_maturity_cents(account.balance_cents)
          }
        end
      end

      def liability_preview
        return unless deal.active? || deal.settled?

        deal.liability_eur_cents(at_height: deal.maturity_block_height || ChainState.block_height)
      end
    end
  end
end
