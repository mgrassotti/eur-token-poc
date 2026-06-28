# frozen_string_literal: true

module Dlc
  # Distributes the peg_pot released by the CET to the individual holders,
  # pro-rata on the current RGB/token allocation at maturity.
  #
  # The DLC CET pays the whole peg_pot to the peg/distributor side; this service
  # fans it out to each holder. Baseline is a single on-chain payout via the ddk
  # node (addresses resolved from each holder's RLN node). The atomic LN variant
  # would bind each receipt to the oracle secret (HODL invoice) so EURT
  # redemption and BTC receipt settle atomically — unavailable on the vendored
  # RLN, hence the on-chain baseline (see DLC-RLN-PLAN.md caveats).
  class Distribution
    class Error < StandardError; end

    Payout = Data.define(:user, :sats, :address, :txid)

    DEFAULT_ADDRESS_RESOLVER = ->(user) { Rgb::Nodes.for_user(user).address.fetch("address") }

    def self.call(budget:, peg_pot_sats:, node: nil, address_resolver: DEFAULT_ADDRESS_RESOLVER)
      new(budget:, peg_pot_sats:, node:, address_resolver:).call
    end

    def initialize(budget:, peg_pot_sats:, node: nil, address_resolver: DEFAULT_ADDRESS_RESOLVER)
      @budget = budget
      @peg_pot_sats = Integer(peg_pot_sats)
      @node = node || NodeClient.default
      @address_resolver = address_resolver
    end

    def call
      contract = budget.dlc_contract
      raise Error, "Nessun contratto DLC per il budget #{budget.id}" if contract.nil?

      shares = compute_shares
      return [] if shares.empty?

      outputs = shares.map { |s| { address: address_resolver.call(s[:user]), sats: s[:sats] } }
      result = node.distribute(contract_id: contract.ddk_contract_id, payouts: outputs)

      persist!(result.txid, shares, outputs)

      shares.each_with_index.map do |s, i|
        Payout.new(user: s[:user], sats: s[:sats], address: outputs[i][:address], txid: result.txid)
      end
    rescue NodeClient::Error, Rgb::Nodes::Error, Rgb::LightningClient::Error => e
      raise Error, "Distribuzione DLC fallita: #{e.message}"
    end

    private

    attr_reader :budget, :peg_pot_sats, :node, :address_resolver

    # Largest-remainder-free split: each holder floors their pro-rata share and
    # the last holder absorbs the rounding remainder, so the sum equals peg_pot.
    def compute_shares
      accounts = budget.token_accounts.where("balance_cents > 0").order(:id).to_a
      return [] if accounts.empty?

      total_cents = accounts.sum(&:balance_cents)
      raise Error, "Allocazione holder vuota" if total_cents.zero?

      shares = []
      assigned = 0
      accounts[0..-2].each do |account|
        sats = (peg_pot_sats * account.balance_cents) / total_cents
        shares << { user: account.user, sats: sats }
        assigned += sats
      end

      last = accounts.last
      shares << { user: last.user, sats: peg_pot_sats - assigned }
      shares
    end

    def persist!(txid, shares, outputs)
      package = budget.recovery_package&.deep_dup || {}
      package["dlc_distribution"] = {
        "txid" => txid,
        "peg_pot_sats" => peg_pot_sats,
        "payouts" => shares.each_with_index.map do |s, i|
          { "user_id" => s[:user].id, "sats" => s[:sats], "address" => outputs[i][:address] }
        end
      }
      budget.update!(recovery_package: package)
    end
  end
end
