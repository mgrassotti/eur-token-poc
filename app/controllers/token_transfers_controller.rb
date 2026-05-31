# frozen_string_literal: true

class TokenTransfersController < ApplicationController
  before_action :require_login
  before_action :set_budget

  def new
    @users = User.where(admin: false).where.not(id: current_user.id).order(:name)
  end

  def create
    to_user = User.where(admin: false).find(params[:to_user_id])
    amount_cents = (params[:amount_eur].to_d * 100).round

    Tokens::TransferService.call(
      budget: @budget,
      from_user: current_user,
      to_user: to_user,
      amount_cents: amount_cents
    )

    redirect_to root_path, notice: "Inviati #{BtcConversion.format_eur(amount_cents)} a #{to_user.name}."
  rescue Tokens::TransferService::Error => e
    flash.now[:alert] = e.message
    @users = User.where(admin: false).where.not(id: current_user.id).order(:name)
    render :new, status: :unprocessable_entity
  end

  private

  def set_budget
    @budget = Budget.find(params[:budget_id])
    return if @budget.active?

    redirect_to @budget, alert: "Token transfers are only allowed on active budgets."
  end
end
