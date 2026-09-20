# frozen_string_literal: true

# Prepares demo users for mobile integration tests (regtest must be up).
bob = User.find_by!(email: "bob@example.com")
amount_sats = 2_000_000

# Phase 2: Check if Bob has a reserve address registered
address = bob.btc_account.reserve_receive_address
if address.blank?
  # Generate address from wallet (still used for DLC operations)
  wallet = L1::UserWallet.for(bob)
  address = wallet.receive_address
  bob.btc_account.update!(reserve_receive_address: address)
  puts "Registered reserve address for Bob: #{address}"
end

# Fund using Phase 2 service
L1::FundReceiveAddressService.call(address: address, amount_sats: amount_sats)
bob.btc_account.reload

puts "Funded Bob reserve: #{bob.btc_account.balance_sats} sats (#{bob.btc_account.reserve_receive_address})"
