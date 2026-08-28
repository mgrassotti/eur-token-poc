# frozen_string_literal: true

module Api
  module V1
    class FundingRequestsController < BaseController
      skip_before_action :authenticate_api_user!
      before_action :optional_authenticate!
      before_action :set_request, only: %i[show submit_utxos]

      def index
        requests = FundingRequest.where(receive_address: indexed_addresses)
                                 .or(FundingRequest.where(user_id: current_user&.id))
                                 .order(created_at: :desc)

        render json: {
          schema_version: 1,
          collection_iban: BankAccount.default.iban,
          collection_bank_name: BankAccount.default.name,
          requests: requests.map { |r| FundingRequestSerializer.render(r) }
        }
      end

      def show
        render json: FundingRequestSerializer.render(@request)
      end

      def create
        request = Funding::CreateRequest.call(
          role: request_params[:role],
          amount_eur_cents: amount_cents,
          receive_address: request_params[:receive_address],
          payout_mode: request_params[:payout_mode],
          payout_iban: request_params[:payout_iban],
          display_name: request_params[:display_name],
          user: current_user
        )
        render json: FundingRequestSerializer.render(request), status: :created
      rescue Funding::CreateRequest::Error => e
        render json: { error: "create_failed", detail: e.message }, status: :unprocessable_entity
      end

      def submit_utxos
        request = Funding::SubmitUtxos.call(
          request: @request,
          inputs: permitted_inputs,
          change_address: params.require(:change_address),
          identity_pubkey: params[:identity_pubkey]
        )
        render json: FundingRequestSerializer.render(request)
      rescue Funding::SubmitUtxos::Error => e
        render json: { error: "utxos_failed", detail: e.message }, status: :unprocessable_entity
      end

      private

      def optional_authenticate!
        @current_user = user_from_bearer_token
      end

      def set_request
        @request = FundingRequest.find(params[:id])
      end

      def indexed_addresses
        Array(params[:address] || params[:addresses]).map { |a| a.to_s.strip }.reject(&:blank?)
      end

      def request_params
        params.require(:funding_request).permit(
          :role, :amount_eur_cents, :amount_eur, :receive_address,
          :payout_mode, :payout_iban, :display_name
        )
      end

      def amount_cents
        raw = request_params
        return raw[:amount_eur_cents].to_i if raw[:amount_eur_cents].present?

        (raw[:amount_eur].to_d * 100).round
      end

      def permitted_inputs
        Array(params.require(:inputs)).map do |item|
          item = item.permit(:txid, :vout, :amount_sats) if item.respond_to?(:permit)
          item.to_h.symbolize_keys
        end
      end
    end
  end
end
