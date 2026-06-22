# frozen_string_literal: true

module Admin
  class ChainStatesController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def update
      height = params[:bitcoin_block_height].to_i
      raise ArgumentError, "Altezza blocco non valida" if height.negative?

      settled_before = Budget.settled.count
      ChainState.update_block_height!(height)
      settled_count = Budget.settled.count - settled_before

      notice = "Altezza blocco aggiornata a #{height}."
      notice += " Settlement automatico eseguito per #{settled_count} deal." if settled_count.positive?

      redirect_to root_path, notice: notice
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to root_path, alert: e.message
    rescue Budgets::AutoSettleService::Error => e
      redirect_to root_path, alert: e.message
    end
  end
end
