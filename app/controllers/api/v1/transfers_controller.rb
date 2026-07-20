# frozen_string_literal: true

module Api
  module V1
    # Wallet-level EURT transfer (spends across active deal balances).
    # Accepts either to_user_id (server mints invoice) or receive_request_id (QR pay).
    class TransfersController < BaseController
      def create
        to_user, amount_cents, rgb_recipient_id, receive_request = resolve_destination!

        if Tokens::Spendable.total_cents_for(current_user).zero?
          return render json: {
            error: "no_balance",
            detail: I18n.t("flash.token_transfers.no_balance")
          }, status: :unprocessable_entity
        end

        parts = Tokens::WalletTransferService.call(
          from_user: current_user,
          to_user: to_user,
          amount_cents: amount_cents,
          rgb_recipient_id: rgb_recipient_id
        )

        receive_request&.mark_paid!(by_user: current_user)

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

      def resolve_destination!
        rid = params[:receive_request_id].presence
        if rid
          request = ReceiveRequest.find_by!(public_id: rid)
          unless request.payable?
            raise Tokens::WalletTransferService::Error,
                  I18n.t(request.paid? ? "services.tokens.transfer.receive_request_paid" : "services.tokens.transfer.receive_request_expired")
          end
          if request.user_id == current_user.id
            raise Tokens::WalletTransferService::Error, I18n.t("services.tokens.transfer.cannot_transfer_to_self")
          end

          amount = request.amount_eur_cents.presence || params[:amount_eur_cents].presence&.to_i
          amount = amount_from_eur_param if amount.blank?
          raise Tokens::WalletTransferService::Error, I18n.t("services.tokens.transfer.invalid_amount") if amount.blank? || amount.to_i <= 0

          if request.amount_eur_cents.present? && amount.to_i != request.amount_eur_cents
            raise Tokens::WalletTransferService::Error, I18n.t("services.tokens.transfer.amount_mismatch")
          end

          return [request.user, amount.to_i, request.recipient_id, request]
        end

        to_user = User.where(admin: false).find(params.require(:to_user_id))
        amount = params[:amount_eur_cents].presence&.to_i || amount_from_eur_param
        raise Tokens::WalletTransferService::Error, I18n.t("services.tokens.transfer.invalid_amount") if amount.blank? || amount.to_i <= 0

        [to_user, amount.to_i, nil, nil]
      end

      def amount_from_eur_param
        return if params[:amount_eur].blank?

        (params[:amount_eur].to_d * 100).round
      end
    end
  end
end
