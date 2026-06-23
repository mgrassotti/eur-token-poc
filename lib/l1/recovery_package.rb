# frozen_string_literal: true

module L1
  # Recovery package export — MULTISIG-SPEC §6.
  class RecoveryPackage
    VERSION = 1

    def self.build(budget:, funding:, escrow:, peg_party:, investor:, bot:)
      new(budget:, funding:, escrow:, peg_party:, investor:, bot:).to_h
    end

    def initialize(budget:, funding:, escrow:, peg_party:, investor:, bot:)
      @budget = budget
      @funding = funding
      @escrow = escrow
      @peg_party = peg_party
      @investor = investor
      @bot = bot
    end

    def to_h
      {
        version: VERSION,
        deal_params: deal_params,
        pubkeys: {
          peg_party: pubkey(@peg_party),
          investor: pubkey(@investor),
          bot: pubkey(@bot)
        },
        escrow: {
          address: @escrow.address,
          redeem_script_hex: @escrow.redeem_script_hex,
          outpoint: "#{@funding.txid}:#{@funding.vout}",
          amount_sats: @funding.escrow_sats
        },
        psbt_funding: { txid: @funding.txid, note: "Broadcast funding tx (§3.3 consolidation)" },
        psbt_maturity_template: { note: "Build at maturity with Payoffs::FloorEurCalculator outputs" },
        psbt_refund_timelock: {
          locktime_height: refund_locktime_height,
          note: "Path B — peg + investor 2-of-3 after refund_delay_blocks"
        },
        oracle_policy: { feeds: ["admin_market_rate"], median: true }
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    private

    def deal_params
      {
        deal_id: @budget.id,
        strike_eur_per_btc: @budget.peg_eur_per_btc&.to_s,
        rate_bps_monthly: @budget.rate_bps_monthly,
        genesis_block_height: @budget.genesis_block_height,
        maturity_block_height: @budget.maturity_block_height,
        refund_delay_blocks: @budget.refund_delay_blocks,
        peg_collateral_sats: @budget.borrower_locked_sats,
        hedge_collateral_sats: @budget.investor_locked_sats
      }
    end

    def refund_locktime_height
      @budget.maturity_block_height.to_i + @budget.refund_delay_blocks
    end

    def pubkey(party)
      party.respond_to?(:public_key_hex) ? party.public_key_hex : party[:public_key_hex]
    end
  end
end
