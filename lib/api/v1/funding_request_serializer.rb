# frozen_string_literal: true

module Api
  module V1
    class FundingRequestSerializer
      def self.render(request)
        new(request).as_json
      end

      def initialize(request)
        @request = request
      end

      def as_json
        {
          id: @request.id.to_s,
          role: @request.role,
          status: @request.status,
          amount_eur_cents: @request.amount_eur_cents,
          remaining_eur_cents: @request.remaining_eur_cents,
          payout_mode: @request.payout_mode,
          payout_iban: @request.payout_iban,
          receive_address: @request.receive_address,
          collection_iban: BankAccount.default.iban,
          collection_bank_name: BankAccount.default.name,
          required_sats: @request.required_sats,
          rate_bps_monthly: Funding::CreateRequest::RATE_BPS,
          term_months: Funding::CreateRequest::TERM_MONTHS,
          budget_id: @request.budget_id&.to_s,
          created_at: @request.created_at.iso8601,
          updated_at: @request.updated_at.iso8601
        }
      end
    end
  end
end
