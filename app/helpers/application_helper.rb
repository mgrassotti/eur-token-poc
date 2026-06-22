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
    tag.span budget.status.titleize, class: "badge text-bg-#{color}"
  end

  def ricarica_balance_cents(budget, user)
    account = user.token_accounts.find_by(budget: budget)
    return account.balance_cents if account&.balance_cents.to_i.positive?
    return budget.amount_eur_cents unless budget.settled?

    0
  end

  def ricarica_scadenza_line(budget, balance_cents:)
    line = l(budget.period_end, format: :long)
    if budget.maturity_block_height
      line += " (blocco #{number_with_delimiter(budget.maturity_block_height)})"
    end
    if balance_cents.positive?
      line += " — #{format_eur(balance_cents)}"
      line += " — interessi #{format_eur(budget.holder_interest_at_maturity_cents(balance_cents))}"
    end
    line
  end
end
