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

    # Resolve a holder's on-chain BTC payout address from their RLN node,
    # initializing/unlocking it first (like the other RGB write paths) so a
    # locked node doesn't abort settlement.
    DEFAULT_ADDRESS_RESOLVER = lambda do |user|
      Rgb::WalletSetupService.ensure_for!(user).address.fetch("address")
    end

    def self.call(budget:, peg_pot_sats:, node: nil, address_resolver: DEFAULT_ADDRESS_RESOLVER, shares: nil)
      new(budget:, peg_pot_sats:, node:, address_resolver:, shares:).call
    end

    def initialize(budget:, peg_pot_sats:, node: nil, address_resolver: DEFAULT_ADDRESS_RESOLVER, shares: nil)
      @budget = budget
      @peg_pot_sats = Integer(peg_pot_sats)
      @node = node || NodeClient.default
      @address_resolver = address_resolver
      # Optional pre-redemption snapshot [{user:, cents:}]. Settlement zeroes the
      # token balances during redemption, so the caller passes the maturity
      # allocation here; otherwise we read the live balances from the DB.
      @shares_snapshot = shares
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
      allocations = holder_allocations
      return [] if allocations.empty?

      total_cents = allocations.sum { |a| a[:cents] }
      raise Error, "Allocazione holder vuota" if total_cents.zero?

      shares = []
      assigned = 0
      allocations[0..-2].each do |allocation|
        sats = (peg_pot_sats * allocation[:cents]) / total_cents
        shares << { user: allocation[:user], sats: sats }
        assigned += sats
      end

      last = allocations.last
      shares << { user: last[:user], sats: peg_pot_sats - assigned }
      shares
    end

    # Holder cents at maturity: the explicit pre-redemption snapshot when given,
    # otherwise the live token balances.
    def holder_allocations
      if @shares_snapshot
        @shares_snapshot.filter_map do |s|
          cents = Integer(s[:cents])
          { user: s[:user], cents: cents } if cents.positive?
        end
      else
        budget.token_accounts.where("balance_cents > 0").order(:id).to_a
          .map { |a| { user: a.user, cents: a.balance_cents } }
      end
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
