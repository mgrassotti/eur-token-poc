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

  def budget_status_badge(budget)
    color = { "pending" => "warning", "active" => "success", "settled" => "secondary" }[budget.status]
    label = { "pending" => "In attesa", "active" => "Attiva", "settled" => "Chiusa" }[budget.status]
    tag.span label, class: "badge text-bg-#{color}"
  end

  def budget_ltv_badge(budget, btc_eur_per_btc)
    ltv = budget.loan_to_value_ratio(btc_eur_per_btc)
    return tag.span "LTV —", class: "badge text-bg-secondary" unless ltv

    color = if ltv >= Budget::LIQUIDATION_LTV_THRESHOLD
              "danger"
            elsif ltv >= Budget::MARGIN_CALL_LTV_THRESHOLD
              "warning"
            elsif ltv < Budget::INVESTOR_YIELD_LTV_THRESHOLD
              "info"
            else
              "secondary"
            end
    tag.span "LTV #{number_to_percentage(ltv * 100, precision: 0)}", class: "badge text-bg-#{color}"
  end

  def ricarica_balance_cents(budget, user)
    account = user.token_accounts.find_by(budget: budget)
    return account.balance_cents if account&.balance_cents.to_i.positive?
    return budget.amount_eur_cents unless budget.settled?

    0
  end
end
