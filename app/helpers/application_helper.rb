# frozen_string_literal: true

module ApplicationHelper
  def format_sats(sats)
    BtcConversion.format_btc(sats)
  end

  def format_eur(cents)
    BtcConversion.format_eur(cents)
  end

  def budget_status_badge(budget)
    color = { "pending" => "warning", "active" => "success", "settled" => "secondary" }[budget.status]
    tag.span budget.status.titleize, class: "badge text-bg-#{color}"
  end
end
