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

  def ricarica_balance_cents(budget, user)
    account = user.token_accounts.find_by(budget: budget)
    return account.balance_cents if account&.balance_cents.to_i.positive?
    return budget.amount_eur_cents unless budget.settled?

    0
  end
end
