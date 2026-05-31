# frozen_string_literal: true

password = "password"

users = {
  alice: { name: "Alice", email: "alice@example.com", sats: 10_000_000 },
  bob: { name: "Bob", email: "bob@example.com", sats: 5_000_000 },
  claude: { name: "Claude", email: "claude@example.com", sats: 0 },
  david: { name: "David", email: "david@example.com", sats: 0 }
}

records = users.transform_values do |attrs|
  user = User.find_or_initialize_by(email: attrs[:email])
  user.assign_attributes(name: attrs[:name], password: password, password_confirmation: password)
  user.save!
  user.btc_account.update!(balance_sats: attrs[:sats])
  user
end

alice = records[:alice]

Budget.find_or_create_by!(
  borrower: alice,
  amount_eur_cents: 100_000,
  collateral_eur_cents: 200_000,
  status: :pending,
  period_start: Date.current.beginning_of_month,
  period_end: Date.current.end_of_month
) do |budget|
  budget.investor = nil
end

puts "Seeded #{User.count} users. Login with any *@example.com / password"
puts "Alice has #{BtcConversion.format_btc(records[:alice].balance_sats)}, pending 1000 EUR budget"
