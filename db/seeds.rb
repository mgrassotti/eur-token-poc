# frozen_string_literal: true

password = "password"

users = {
  admin: { name: "Admin", email: "admin@example.com", sats: 0, admin: true },
  alice: { name: "Alice", email: "alice@example.com", sats: 10_000_000, admin: false },
  bob: { name: "Bob", email: "bob@example.com", sats: 20_000_000, admin: false },
  claude: { name: "Claude", email: "claude@example.com", sats: 0, admin: false },
  david: { name: "David", email: "david@example.com", sats: 0, admin: false }
}

records = users.transform_values do |attrs|
  user = User.find_or_initialize_by(email: attrs[:email])
  user.assign_attributes(
    name: attrs[:name],
    password: password,
    password_confirmation: password,
    admin: attrs[:admin]
  )
  user.save!
  user.btc_account.update!(balance_sats: attrs[:sats])
  user
end

alice = records[:alice]

DemoData::ResetService.call

Budgets::CreateService.call(
  borrower: alice,
  amount_eur_cents: 100_000,
  period_start: Date.current.beginning_of_month,
  period_end: Date.current.end_of_month
)

alice.reload
puts "Seeded #{User.count} users."
puts "Admin: admin@example.com / password"
puts "Alice has #{BtcConversion.format_btc(alice.balance_sats)} on conto risparmio, pending budget spesa"
