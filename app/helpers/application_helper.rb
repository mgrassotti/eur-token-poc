# frozen_string_literal: true

module ApplicationHelper
  def format_sats(sats)
    BtcConversion.format_btc(sats)
  end

  def format_eur(cents)
    BtcConversion.format_eur(cents)
  end

  def format_savings_eur(amount)
    BtcConversion.format_eur_amount(amount)
  end

  alias format_eur_amount format_savings_eur

  def truncate_hex(value, leading: 8, trailing: 8)
    return "—" if value.blank?

    str = value.to_s
    return str if str.length <= leading + trailing + 1

    "#{str.first(leading)}…#{str.last(trailing)}"
  end

  def budget_status_badge(budget)
    color = { "pending" => "warning", "active" => "success", "settled" => "secondary" }[budget.status]
    label = t("budget.statuses.#{budget.status}")
    tag.span label, class: "badge text-bg-#{color}"
  end

  def budget_ltv_badge(budget, btc_eur_per_btc)
    ltv = budget.loan_to_value_ratio(btc_eur_per_btc)
    return tag.span t("dashboard.common.ltv_missing"), class: "badge text-bg-secondary" unless ltv

    color = if ltv >= Budget::LIQUIDATION_LTV_THRESHOLD
              "danger"
            elsif ltv >= Budget::MARGIN_CALL_LTV_THRESHOLD
              "warning"
            elsif ltv < Budget::INVESTOR_YIELD_LTV_THRESHOLD
              "info"
            else
              "secondary"
            end
    tag.span t("dashboard.common.ltv_value", value: number_to_percentage(ltv * 100, precision: 0)),
             class: "badge text-bg-#{color}"
  end

  def fund_importo_cents(user, budget)
    if budget.borrower_id == user.id && !budget.pending?
      budget.amount_eur_cents
    else
      user.received_token_transfers.where(budget: budget).sum(:amount_cents)
    end
  end

  def first_token_received_at(user, budget)
    transfer_at = user.received_token_transfers.where(budget: budget).minimum(:created_at)

    if budget.borrower_id == user.id && !budget.pending?
      mint_at = user.token_accounts.find_by(budget: budget)&.created_at
      [mint_at, transfer_at].compact.min
    else
      transfer_at
    end
  end
end
