# frozen_string_literal: true

module Api
  module V1
    class ReceiveRequestsController < BaseController
      def create
        amount = params[:amount_eur_cents].presence&.to_i
        request = Rgb::ReceiveRequestService.call(user: current_user, amount_cents: amount)

        render json: serialize(request), status: :created
      rescue Rgb::ReceiveRequestService::Error => e
        render json: { error: "receive_request_failed", detail: e.message }, status: :unprocessable_entity
      end

      def show
        request = ReceiveRequest.find_by!(public_id: params[:id])
        render json: serialize(request)
      end

      private

      def serialize(request)
        {
          schema_version: 1,
          id: request.public_id,
          user: { id: request.user_id, name: request.user.name },
          amount_eur_cents: request.amount_eur_cents,
          recipient_id: request.recipient_id,
          invoice: request.invoice,
          qr_payload: request.qr_payload,
          expires_at: request.expires_at.iso8601,
          paid: request.paid?,
          expired: request.expired?
        }
      end
    end
  end
end
