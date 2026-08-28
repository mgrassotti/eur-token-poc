# frozen_string_literal: true

module Api
  module V1
    class BankController < BaseController
      skip_before_action :authenticate_api_user!

      def show
        bank = BankAccount.default
        render json: {
          name: bank.name,
          iban: bank.iban,
          balance_eur_cents: bank.balance_eur_cents
        }
      end
    end
  end
end
