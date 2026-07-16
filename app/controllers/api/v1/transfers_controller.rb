# frozen_string_literal: true

module Api
  module V1
    # Wallet-level EURT transfer (spends across active deal balances).
    class TransfersController < BaseController
      def create
        to_user = User.where(admin: false).find(transfer_params[:to_user_id])
        amount_cents = transfer_params[:amount_eur_cents]

        if Tokens::Spendable.total_cents_for(current_user).zero?
          return render json: {
            error: "no_balance",
            detail: I18n.t("flash.token_transfers.no_balance")
          }, status: :unprocessable_entity
        end

        parts = Tokens::WalletTransferService.call(
          from_user: current_user,
          to_user: to_user,
          amount_cents: amount_cents
        )

        render json: {
          schema_version: 1,
          amount_cents: amount_cents,
          to_user: { id: to_user.id, name: to_user.name },
          transfers: parts.map do |part|
            {
              deal_id: part.budget.id.to_s,
              amount_cents: part.amount_cents
            }
          end
        }, status: :created
      rescue ActiveRecord::RecordNotFound
        render json: { error: "recipient_not_found" }, status: :not_found
      rescue Tokens::WalletTransferService::Error => e
        render json: { error: "transfer_failed", detail: e.message }, status: :unprocessable_entity
      end

      private

      def transfer_params
        raw = params.permit(:to_user_id, :amount_eur_cents, :amount_eur)
        amount_cents = raw[:amount_eur_cents]
        if amount_cents.blank? && raw[:amount_eur].present?
          amount_cents = (raw[:amount_eur].to_d * 100).round
        end
        { to_user_id: raw[:to_user_id], amount_eur_cents: amount_cents.to_i }
      end
    end
  end
end
