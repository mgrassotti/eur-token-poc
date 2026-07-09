# frozen_string_literal: true

class BudgetRecoveryPackagesController < ApplicationController
  before_action :require_login
  before_action :set_budget

  def show
    unless authorized_for_recovery_package?
      redirect_to root_path, alert: t("flash.recovery_packages.unauthorized")
      return
    end

    unless @budget.recovery_package.present?
      redirect_to @budget, alert: t("flash.recovery_packages.missing")
      return
    end

    send_data(
      JSON.pretty_generate(@budget.recovery_package),
      filename: "recovery_package_budget_#{@budget.id}.json",
      type: "application/json",
      disposition: "attachment"
    )
  end

  private

  def set_budget
    @budget = Budget.find(params[:budget_id])
  end

  def authorized_for_recovery_package?
    return true if admin?

    [ @budget.borrower_id, @budget.investor_id ].compact.include?(current_user.id)
  end
end
