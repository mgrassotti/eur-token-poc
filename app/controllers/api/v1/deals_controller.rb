# frozen_string_literal: true

module Api
  module V1
    class DealsController < BaseController
      skip_before_action :authenticate_api_user!, only: %i[index show create accept funding_signature]
      before_action :optional_authenticate!, only: %i[index show create accept funding_signature]
      before_action :set_deal, only: %i[show accept funding_signature]

      def index
        market_rate = MarketRate.current
        deals = visible_deals.includes(:borrower, :investor).order(created_at: :desc)

        render json: {
          schema_version: 1,
          deals: deals.map { |deal| DealSerializer.render(deal, market_rate: market_rate) }
        }
      end

      def show
        render json: deal_payload(@deal)
      end

      def create
        deal = Budgets::CreateService.call(
          borrower: current_user,
          funding_address: deal_params[:funding_address],
          commitment_psbt: deal_params[:commitment_psbt],
          borrower_name: deal_params[:borrower_name],
          amount_eur_cents: deal_params[:amount_eur_cents],
          period_start: deal_params[:period_start],
          period_end: deal_params[:period_end]
        )

        render json: deal_payload(deal), status: :created
      rescue Budgets::CreateService::Error => e
        render json: { error: "create_failed", detail: e.message }, status: :unprocessable_entity
      end

      def accept
        investor = resolve_investor!
        funding = Budgets::FundingParams.from_hash(accept_funding_params)

        # Prefer reserved borrower outpoints from create when client omits peg_inputs.
        if funding.peg_inputs.empty? && @deal.reserved_outpoints.present?
          funding = Budgets::FundingParams.new(
            peg_inputs: @deal.reserved_outpoints,
            investor_inputs: funding.investor_inputs,
            peg_change_address: funding.peg_change_address.presence || @deal.funding_address,
            investor_change_address: funding.investor_change_address,
            investor_payout_address: funding.investor_payout_address,
            peg_identity_pubkey: funding.peg_identity_pubkey.presence || @deal.peg_party_pubkey || "02#{"a" * 64}",
            investor_identity_pubkey: funding.investor_identity_pubkey
          )
        end

        deal = Budgets::ActivateService.call(
          budget: @deal,
          investor: investor,
          funding: funding,
          verify_utxos: true
        )

        render json: deal_payload(deal)
      rescue Budgets::ActivateService::Error, Budgets::FundingParams::Error,
             L1::UtxoSetValidator::Error, L1::ProvisionEscrowService::Error,
             Rgb::LightningClient::Error, Rgb::Nodes::Error, Rgb::WalletSetupService::Error,
             Rgb::LibIssueService::Error, Rgb::IssueService::Error,
             Dlc::ContractSetupService::Error => e
        render json: { error: "accept_failed", detail: e.message }, status: :unprocessable_entity
      end

      def funding_signature
        deal = Budgets::SubmitFundingSignatureService.call(
          budget: @deal,
          funding_address: params.require(:funding_address),
          signed_psbt: params.require(:signed_psbt)
        )

        render json: deal_payload(deal)
      rescue Budgets::SubmitFundingSignatureService::Error, Budgets::FinalizeFundingService::Error => e
        render json: { error: "funding_signature_failed", detail: e.message }, status: :unprocessable_entity
      end

      private

      def visible_deals
        if current_user&.admin?
          Budget.all
        elsif current_user
          Budget.where(borrower_id: current_user.id)
                .or(Budget.where(investor_id: current_user.id))
                .or(Budget.awaiting_investor)
        else
          Budget.marketplace_visible
        end
      end

      def optional_authenticate!
        @current_user = user_from_bearer_token
      end

      def set_deal
        @deal = Budget.find(params[:id])
      end

      def deal_payload(deal)
        DealSerializer.render(deal, market_rate: MarketRate.current, detail: true)
      end

      def deal_params
        raw = params.require(:deal).permit(
          :amount_eur_cents, :amount_eur, :period_start, :period_end,
          :funding_address, :commitment_psbt, :borrower_name
        )
        amount_cents = raw[:amount_eur_cents]
        if amount_cents.blank? && raw[:amount_eur].present?
          amount_cents = (raw[:amount_eur].to_d * 100).round
        end

        {
          amount_eur_cents: amount_cents.to_i,
          period_start: raw[:period_start],
          period_end: raw[:period_end],
          funding_address: raw[:funding_address],
          commitment_psbt: raw[:commitment_psbt],
          borrower_name: raw[:borrower_name]
        }
      end

      def accept_funding_params
        raw = params.permit(
          :funding_address, :investor_name,
          :peg_change_address, :borrower_change_address,
          :investor_change_address, :investor_payout_address,
          :peg_identity_pubkey, :borrower_identity_pubkey, :investor_identity_pubkey,
          peg_inputs: %i[txid vout amount_sats],
          borrower_inputs: %i[txid vout amount_sats],
          investor_inputs: %i[txid vout amount_sats]
        )
        raw.to_h
      end

      def resolve_investor!
        if current_user
          if @deal.borrower_id == current_user.id
            raise Budgets::ActivateService::Error, "cannot_invest_own_deal"
          end
          return current_user
        end

        address = params[:funding_address].to_s.strip
        raise ActionController::ParameterMissing, "funding_address" if address.blank?

        if @deal.funding_address.present? && address == @deal.funding_address
          raise Budgets::ActivateService::Error, "cannot_invest_own_deal"
        end

        Users::GuestFinder.find_or_create_by_address!(
          address: address,
          name: params[:investor_name]
        )
      end
    end
  end
end
