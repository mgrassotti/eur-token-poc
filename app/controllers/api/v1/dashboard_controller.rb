# frozen_string_literal: true

module Api
  module V1
    class DashboardController < BaseController
      def show
        market_rate = MarketRate.current

        render json: {
          schema_version: 1,
          user: {
            id: current_user.id,
            name: current_user.name,
            email: current_user.email,
            admin: current_user.admin?
          },
          market_rate: market_rate_payload(market_rate),
          savings: savings_payload(market_rate),
          spending_eur_cents: Tokens::Spendable.total_cents_for(current_user),
          max_borrowable_eur_cents: Budgets::ReserveRequirement.max_eur_cents_for(current_user),
          investment_sats: current_user.invested_budgets.active.sum(:investor_locked_sats),
          borrowed_deals: current_user.borrowed_budgets.order(created_at: :desc).map do |deal|
            DealSerializer.render(deal, market_rate: market_rate)
          end,
          investable_deals: investable_deals(market_rate),
          fund_positions: fund_positions,
          margin_call_deals: margin_call_deals(market_rate)
        }
      end

      private

      def market_rate_payload(market_rate)
        {
          btc_eur_per_btc: market_rate.btc_eur_per_btc&.to_f,
          bitcoin_block_height: market_rate.bitcoin_block_height,
          set: market_rate.set?
        }
      end

      def savings_payload(market_rate)
        # Phase 2: Mobile clients show their BDK wallet balance directly
        # Server no longer tracks reserve balance
        { sats: 0, eur: 0 }
      end

      def investable_deals(market_rate)
        Budget.awaiting_investor
             .includes(:borrower)
             .order(created_at: :desc)
             .reject { |deal| deal.borrower_id == current_user.id }
             .map { |deal| DealSerializer.render(deal, market_rate: market_rate) }
      end

      def fund_positions
        return [] if current_user.admin?

        Tokens::Spendable.fund_positions_for(current_user).map do |position|
          {
            deal_id: position.budget.id.to_s,
            interest_cents: position.budget.holder_interest_at_maturity_cents(position.balance_cents),
            period_end: position.budget.period_end.iso8601
          }
        end
      end

      def margin_call_deals(market_rate)
        Budgets::MarginCall.budgets_for(current_user, market_rate: market_rate).map do |deal|
          DealSerializer.render(deal, market_rate: market_rate)
        end
      end
    end
  end
end
