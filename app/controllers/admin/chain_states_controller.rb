# frozen_string_literal: true

module Admin
  class ChainStatesController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def update
      height = params[:bitcoin_block_height].to_i
      raise ArgumentError, I18n.t("flash.admin.chain_state.invalid_height") if height.negative?

      settled_before = Budget.settled.count
      result = ChainState.update_block_height!(height)
      settled_count = Budget.settled.count - settled_before

      notice = t("flash.admin.chain_state.updated", height: height)
      notice += " #{t("flash.admin.chain_state.auto_settled", count: settled_count)}" if settled_count.positive?
      if result.blocked_budget_ids.any?
        notice += " #{t("flash.admin.chain_state.settlement_blocked",
          ids: result.blocked_budget_ids.join(", "))}"
      end

      redirect_to root_path, notice: notice
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to root_path, alert: e.message
    rescue Budgets::AutoSettleService::Error, Settlements::ExecuteService::Error => e
      redirect_to root_path, alert: e.message
    end
  end
end
