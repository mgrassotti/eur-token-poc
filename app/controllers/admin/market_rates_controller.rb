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
      redirect_to root_path, notice: "Cambio BTC/€ aggiornato a #{params[:btc_eur_per_btc]} €/BTC."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to root_path, alert: e.record.errors.full_messages.to_sentence
    end
  end
end
