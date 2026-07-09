# frozen_string_literal: true

module Admin
  class MarketRatesController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def update
      rate = MarketRate.current
      rate.update!(
        btc_eur_per_btc: params[:btc_eur_per_btc],
        set_by: current_user
      )
      liquidations = Budgets::AutoLiquidationService.call(market_rate: rate, set_by: current_user)
      settled_ids = liquidations.map { |result| result.settlement.budget_id }
      Budgets::ReconcileService.call(exclude_budget_ids: settled_ids)
      margin_calls = Budget.active.where.not(id: settled_ids).select { |b| b.margin_call_threshold_reached?(rate.btc_eur_per_btc) }
      notice = if liquidations.any?
        ids = settled_ids.join(", ")
        t("flash.admin.market_rate.liquidations",
          threshold: (Budget::LIQUIDATION_LTV_THRESHOLD * 100).to_i,
          ids: ids,
          rate: params[:btc_eur_per_btc])
      else
        t("flash.admin.market_rate.updated", rate: params[:btc_eur_per_btc])
      end
      if margin_calls.any?
        ids = margin_calls.map(&:id).join(", ")
        notice += " #{t("flash.admin.market_rate.margin_calls",
          threshold: (Budget::MARGIN_CALL_LTV_THRESHOLD * 100).to_i,
          ids: ids)}"
      end
      redirect_to root_path, notice: notice
    rescue ActiveRecord::RecordInvalid => e
      redirect_to root_path, alert: e.record.errors.full_messages.to_sentence
    end
  end
end
