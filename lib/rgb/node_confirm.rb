# frozen_string_literal: true

module Rgb
  # Regtest helper that confirms RGB on-chain operations so balances reach the
  # "settled" state synchronously: mines blocks and refreshes the involved nodes
  # a couple of rounds. No-op when bitcoind/regtest is unavailable (on real
  # networks confirmations and refreshes happen out of band).
  module NodeConfirm
    DEFAULT_ROUNDS = 2

    module_function

    def settle_users!(*users, rounds: DEFAULT_ROUNDS)
      clients = users.compact.uniq.filter_map do |user|
        Nodes.for_user(user) if Nodes.for_user?(user)
      end
      settle_clients!(*clients, rounds: rounds)
    end

    def settle_clients!(*clients, rounds: DEFAULT_ROUNDS)
      clients = clients.compact
      return if clients.empty?
      return unless regtest?

      harness = L1::RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET)
      rounds.times do
        refresh!(clients)
        harness.mine_blocks(1)
      end
      refresh!(clients)
    end

    def mine!(blocks = 1)
      return unless regtest?

      L1::RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET).mine_blocks(blocks)
    end

    def refresh!(clients)
      Array(clients).each do |client|
        client.refresh_transfers
      rescue LightningClient::Error
        nil
      end
    end

    def regtest?
      L1::Bitcoind::Client.new.available?
    rescue StandardError
      false
    end
  end
end
