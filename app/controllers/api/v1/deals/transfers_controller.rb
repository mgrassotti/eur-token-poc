# frozen_string_literal: true

module Api
  module V1
    module Deals
      class TransfersController < BaseController
        before_action :set_deal

        def index
          transfers = @deal.token_transfers.includes(:from_user, :to_user).order(created_at: :desc)

          render json: {
            schema_version: 1,
            deal_id: @deal.id.to_s,
            transfers: transfers.map { |transfer| transfer_json(transfer) }
          }
        end

        def create
          to_user = User.where(admin: false).find(transfer_params[:to_user_id])

          parts = Tokens::WalletTransferService.call(
            from_user: current_user,
            to_user: to_user,
            amount_cents: transfer_params[:amount_eur_cents],
            preferred_budget: @deal
          )

          render json: {
            schema_version: 1,
            transfers: parts.map do |part|
              {
                deal_id: part.budget.id.to_s,
                amount_cents: part.amount_cents,
                to_user: { id: to_user.id, name: to_user.name }
              }
            end
          }, status: :created
        rescue ActiveRecord::RecordNotFound
          render json: { error: "recipient_not_found" }, status: :not_found
        rescue Tokens::WalletTransferService::Error => e
          render json: { error: "transfer_failed", detail: e.message }, status: :unprocessable_entity
        end

        private

        def set_deal
          @deal = Budget.find(params[:deal_id])
        end

        def transfer_params
          raw = params.permit(:to_user_id, :amount_eur_cents, :amount_eur)
          amount_cents = raw[:amount_eur_cents]
          if amount_cents.blank? && raw[:amount_eur].present?
            amount_cents = (raw[:amount_eur].to_d * 100).round
          end
          { to_user_id: raw[:to_user_id], amount_eur_cents: amount_cents.to_i }
        end

        def transfer_json(transfer)
          {
            id: transfer.id,
            amount_cents: transfer.amount_cents,
            from_user: { id: transfer.from_user_id, name: transfer.from_user.name },
            to_user: { id: transfer.to_user_id, name: transfer.to_user.name },
            created_at: transfer.created_at.iso8601
          }
        end
      end
    end
  end
end
