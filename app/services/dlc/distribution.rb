# frozen_string_literal: true

module Dlc
  # Distributes CET outputs to holders at settlement.
  #
  # When +holder_targets+ is given, each holder is paid the exact FloorEUR sats
  # (funded from the peg + investor CET outputs combined). Otherwise falls back
  # to splitting +peg_pot_sats+ pro-rata on token balances at maturity.
  #
  # Baseline is a single on-chain payout via the ddk
  # node (addresses resolved from each holder's L1 reserve wallet). The atomic LN
  # variant would bind each receipt to the oracle secret (HODL invoice) so EURT
  # redemption and BTC receipt settle atomically — unavailable on the vendored
  # RLN, hence the on-chain baseline (see DLC-RLN-PLAN.md caveats).
  class Distribution
    class Error < StandardError; end

    Payout = Data.define(:user, :sats, :address, :txid)

    # Resolve a holder's payout address from their L1 reserve wallet so the
    # FloorEUR payout lands in the same balance the dashboard/reserve show (as
    # with the legacy escrow settlement). Settlement then syncs the reserve.
    DEFAULT_ADDRESS_RESOLVER = lambda do |user|
      L1::UserWallet.for(user).receive_address(label: "dlc_payout")
    end

    def self.call(budget:, peg_pot_sats:, node: nil, address_resolver: DEFAULT_ADDRESS_RESOLVER, shares: nil,
                  holder_targets: nil)
      new(budget:, peg_pot_sats:, node:, address_resolver:, shares:, holder_targets:).call
    end

    # Estimated fanout fee when the sidecar spends peg + investor CET outputs.
    def self.fee_estimate(holder_count, fee_rate_sats_vb: 5)
      input_count = 2
      vsize = 11 + 68 * input_count + 31 * (holder_count + 1)
      vsize * fee_rate_sats_vb
    end

    def initialize(budget:, peg_pot_sats:, node: nil, address_resolver: DEFAULT_ADDRESS_RESOLVER, shares: nil,
                   holder_targets: nil)
      @budget = budget
      @peg_pot_sats = Integer(peg_pot_sats)
      @node = node || NodeClient.default
      @address_resolver = address_resolver
      # Optional pre-redemption snapshot [{user:, cents:}]. Settlement zeroes the
      # token balances during redemption, so the caller passes the maturity
      # allocation here; otherwise we read the live balances from the DB.
      @shares_snapshot = shares
      # Optional explicit FloorEUR targets [{user:, sats:}]. When set, these
      # replace the pro-rata peg_pot split (the sidecar funds them from both CET
      # outputs and pushes the fanout fee onto the investor).
      @holder_targets = holder_targets
    end

    def call
      contract = budget.dlc_contract
      raise Error, I18n.t("services.dlc.distribution.missing_contract", budget_id: budget.id) if contract.nil?

      shares = compute_shares
      return [] if shares.empty?

      if contract.direct_payout?
        return persist_direct_payout!(shares)
      end

      outputs = shares.map { |s| { address: address_resolver.call(s[:user]), sats: s[:sats] } }
      result = node.distribute(contract_id: contract.ddk_contract_id, payouts: outputs)
      @last_result = result

      # The node spends the CET outputs and pushes the fanout fee onto the
      # investor side, so holders should receive the exact requested shares.
      actual = actual_amounts(shares, result)
      persist!(result.txid, shares, outputs, actual)

      shares.each_with_index.map do |s, i|
        Payout.new(user: s[:user], sats: actual[i], address: outputs[i][:address], txid: result.txid)
      end
    rescue NodeClient::Error => e
      raise Error, I18n.t("services.dlc.distribution.failed", message: e.message)
    end

    private

    attr_reader :budget, :peg_pot_sats, :node, :address_resolver

    def compute_shares
      if @holder_targets
        return @holder_targets.filter_map do |target|
          sats = Integer(target[:sats])
          { user: target[:user], sats: sats } if sats.positive?
        end
      end

      # Largest-remainder-free split: each holder floors their pro-rata share and
      # the last holder absorbs the rounding remainder, so the sum equals peg_pot.
      allocations = holder_allocations
      return [] if allocations.empty?

      total_cents = allocations.sum { |a| a[:cents] }
      raise Error, I18n.t("services.dlc.distribution.empty_allocations") if total_cents.zero?

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

    # Actual on-chain sats paid per share, from the node response (index-aligned
    # with the requested outputs); falls back to the requested share when the node
    # does not echo detailed amounts (e.g. unit specs with a stubbed node).
    def actual_amounts(shares, result)
      payouts = Array(result.payouts)
      shares.each_with_index.map do |s, i|
        entry = payouts[i]
        value = entry && (entry["sats"] || entry[:sats])
        value ? Integer(value) : s[:sats]
      end
    end

    def persist!(txid, shares, outputs, actual)
      package = budget.recovery_package&.deep_dup || {}
      package["dlc_distribution"] = {
        "txid" => txid,
        "peg_pot_sats" => actual.sum,
        "investor_payout_sats" => @last_result&.investor_payout_sats,
        "investor_payout_address" => @last_result&.investor_payout_address,
        "payouts" => shares.each_with_index.map do |s, i|
          { "user_id" => s[:user].id, "sats" => actual[i], "address" => outputs[i][:address] }
        end
      }
      budget.update!(recovery_package: package)
    end

    def persist_direct_payout!(shares)
      outputs = shares.map { |s| { address: address_resolver.call(s[:user]), sats: s[:sats] } }
      txid = budget.dlc_settlement&.cet_txid.presence || budget.recovery_package&.dig("settlement_txid")
      persist!(txid, shares, outputs, shares.map { |s| s[:sats] })
      investor_sats = budget.dlc_settlement&.investor_sats.to_i
      package = budget.recovery_package&.deep_dup || {}
      package["dlc_distribution"] = (package["dlc_distribution"] || {}).merge(
        "direct_payout" => true,
        "investor_payout_sats" => investor_sats,
        "investor_payout_address" => budget.investor_payout_address
      )
      budget.update!(recovery_package: package)

      shares.each_with_index.map do |s, i|
        Payout.new(user: s[:user], sats: s[:sats], address: outputs[i][:address], txid: txid)
      end
    end
  end
end
