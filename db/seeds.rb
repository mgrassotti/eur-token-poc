# frozen_string_literal: true

password = "password"

DemoData::ResetService::DEMO_USERS.each do |attrs|
  user = User.find_or_initialize_by(email: attrs[:email])
  user.assign_attributes(
    name: attrs[:name],
    password: password,
    password_confirmation: password,
    admin: attrs[:admin]
  )
  user.save!
end

DemoData::ResetService.call

puts "Seeded #{User.count} users."
puts "Admin: admin@example.com / password"
puts "Conti di riserva a zero — con bin/dev: deposita dal Wallet esterno prima di creare ricariche."
