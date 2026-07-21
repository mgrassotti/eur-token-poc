# frozen_string_literal: true

module Api
  module V1
    module Deals
      class SettlementsController < BaseController
        before_action :set_deal

        def show
          market_rate = MarketRate.current

          if @deal.settlement.present?
            render json: executed_settlement(@deal, market_rate)
          else
            render json: settlement_preview(@deal, market_rate)
          end
        end

        def create
          require_admin!

          result = Settlements::ExecuteService.call(
            budget: @deal,
            end_btc_eur_rate: settlement_params[:end_btc_eur_rate],
            set_by: current_user
          )

          render json: executed_settlement(result.budget, MarketRate.current, result: result), status: :created
        rescue Settlements::ExecuteService::Error => e
          render json: { error: "settlement_failed", detail: e.message }, status: :unprocessable_entity
        end

        private

        def set_deal
          @deal = Budget.find(params[:deal_id])
        end

        def settlement_params
          params.permit(:end_btc_eur_rate)
        end

        def executed_settlement(deal, market_rate, result: nil)
          settlement = deal.settlement
          spot = settlement.end_btc_eur_rate
          payload = {
            schema_version: 1,
            deal_id: deal.id.to_s,
            status: "executed",
            end_btc_eur_rate: spot.to_f,
            total_btc_to_holders_sats: settlement.total_btc_to_holders_sats,
            btc_to_investor_sats: settlement.btc_to_investor_sats,
            executed_at: settlement.executed_at.iso8601,
            # Audit inputs so clients can recompute FloorEUR offline after execution.
            calculation_inputs: calculation_inputs(deal, spot)
          }

          if result
            payload[:payoff] = payoff_json(result.payoff)
            payload[:payouts] = result.payouts.map do |payout|
              {
                user: { id: payout.user.id, name: payout.user.name },
                token_cents: payout.token_cents,
                btc_sats: payout.btc_sats,
                liability_eur_cents: payout.liability_eur_cents,
                eur_at_settlement: payout.eur_at_settlement.to_f
              }
            end
          end

          payload
        end

        def settlement_preview(deal, market_rate)
          spot = market_rate.set? ? market_rate.btc_eur_per_btc.to_d : deal.peg_eur_per_btc
          holders = deal.token_accounts.includes(:user).where("balance_cents > 0").order(:id)

          payoff = if spot.present? && spot.positive? && deal.pool_sats.positive?
                     Payoffs::FloorEurCalculator.call(
                       notional_eur_cents: deal.notional_eur_cents,
                       notional_total_cents: deal.amount_eur_cents,
                       holder_shares_cents: holders.map(&:balance_cents),
                       spot_eur_per_btc: spot,
                       rate_bps_monthly: deal.rate_bps_monthly,
                       months_elapsed: deal.symbolic_months_duration,
                       escrow_total_sats: deal.pool_sats
                     )
                   end

          {
            schema_version: 1,
            deal_id: deal.id.to_s,
            status: "preview",
            end_btc_eur_rate: spot&.to_f,
            ready_for_settlement: deal.ready_for_settlement?,
            # Inputs for on-device FloorEUR recompute (mat-core / mat_sdk).
            calculation_inputs: calculation_inputs(deal, spot),
            payoff: payoff ? payoff_json(payoff) : nil,
            holder_allocations: payoff&.holder_allocations&.each_with_index&.map do |alloc, idx|
              {
                user: { id: holders[idx].user.id, name: holders[idx].user.name },
                share_cents: alloc.share_cents,
                btc_sats: alloc.btc_sats
              }
            end
          }
        end

        # Shared FloorEUR inputs for preview (live spot) and executed (settlement rate).
        def calculation_inputs(deal, spot)
          holders = deal.token_accounts.where("balance_cents > 0").order(:id)
          {
            notional_eur_cents: deal.notional_eur_cents,
            notional_total_cents: deal.amount_eur_cents,
            holder_shares_cents: holders.map(&:balance_cents),
            spot_eur_per_btc: spot&.to_i,
            rate_bps_monthly: deal.rate_bps_monthly,
            months_elapsed: deal.symbolic_months_duration,
            escrow_total_sats: deal.pool_sats,
            mining_fee_sats: Budget::ESTIMATED_SETTLEMENT_FEE_SATS
          }
        end

        def payoff_json(payoff)
          {
            liability_eur_cents: payoff.liability_eur_cents,
            gross_holder_sats: payoff.gross_holder_sats,
            total_holder_sats: payoff.total_holder_sats,
            distributable_sats: payoff.distributable_sats,
            investor_remainder_sats: payoff.investor_remainder_sats,
            insolvent: payoff.insolvent
          }
        end
      end
    end
  end
end
