# frozen_string_literal: true

# Prepares demo users for mobile integration tests (regtest must be up).
bob = User.find_by!(email: "bob@example.com")
amount_sats = 2_000_000

L1::DepositReserveService.call(user: bob, amount_sats: amount_sats)
bob.btc_account.reload

puts "Funded Bob reserve: #{bob.btc_account.balance_sats} sats (#{bob.btc_account.reserve_receive_address})"
