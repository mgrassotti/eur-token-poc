# frozen_string_literal: true

module Api
  module V1
    class DealsController < BaseController
      before_action :set_deal, only: %i[show accept]

      def index
        market_rate = MarketRate.current
        deals = visible_deals.includes(:borrower, :investor).order(created_at: :desc)

        render json: {
          schema_version: 1,
          deals: deals.map { |deal| DealSerializer.render(deal, market_rate: market_rate) }
        }
      end

      def show
        render json: DealSerializer.render(@deal, market_rate: MarketRate.current, detail: true)
      end

      def create
        deal = Budgets::CreateService.call(
          borrower: current_user,
          amount_eur_cents: deal_params[:amount_eur_cents],
          period_start: deal_params[:period_start],
          period_end: deal_params[:period_end]
        )

        render json: DealSerializer.render(deal, market_rate: MarketRate.current, detail: true),
               status: :created
      rescue Budgets::CreateService::Error => e
        render json: { error: "create_failed", detail: e.message }, status: :unprocessable_entity
      end

      def accept
        if @deal.borrower_id == current_user.id
          return render json: { error: "cannot_invest_own_deal" }, status: :unprocessable_entity
        end

        unless MarketRate.current.set?
          return render json: { error: "market_rate_required" }, status: :unprocessable_entity
        end

        deal = Budgets::ActivateService.call(budget: @deal, investor: current_user)

        render json: DealSerializer.render(deal, market_rate: MarketRate.current, detail: true)
      rescue Budgets::ActivateService::Error, L1::ProvisionEscrowService::Error,
             Rgb::LightningClient::Error, Rgb::Nodes::Error, Rgb::WalletSetupService::Error,
             Rgb::LibIssueService::Error, Rgb::IssueService::Error,
             Dlc::ContractSetupService::Error => e
        render json: { error: "accept_failed", detail: e.message }, status: :unprocessable_entity
      end

      private

      def visible_deals
        if current_user.admin?
          Budget.all
        else
          Budget.where(borrower_id: current_user.id)
                .or(Budget.where(investor_id: current_user.id))
                .or(Budget.awaiting_investor)
        end
      end

      def set_deal
        @deal = Budget.find(params[:id])
      end

      def deal_params
        raw = params.require(:deal).permit(:amount_eur_cents, :amount_eur, :period_start, :period_end)
        amount_cents = raw[:amount_eur_cents]
        if amount_cents.blank? && raw[:amount_eur].present?
          amount_cents = (raw[:amount_eur].to_d * 100).round
        end

        {
          amount_eur_cents: amount_cents.to_i,
          period_start: raw[:period_start],
          period_end: raw[:period_end]
        }
      end
    end
  end
end
