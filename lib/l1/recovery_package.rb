# frozen_string_literal: true

module L1
  class RecoveryPackage
    VERSION = 1

    def self.build(budget:, funding:, escrow:, peg_party:, investor:, refund_psbt: nil)
      new(budget:, funding:, escrow:, peg_party:, investor:, refund_psbt:).to_h
    end

    def initialize(budget:, funding:, escrow:, peg_party:, investor:, refund_psbt: nil)
      @budget = budget
      @funding = funding
      @escrow = escrow
      @peg_party = peg_party
      @investor = investor
      @refund_psbt = refund_psbt
    end

    def to_h
      {
        version: VERSION,
        deal_params: deal_params,
        pubkeys: {
          peg_party: pubkey(@peg_party),
          investor: pubkey(@investor)
        },
        escrow: {
          address: @escrow.address,
          redeem_script_hex: @escrow.redeem_script_hex,
          outpoint: "#{@funding.txid}:#{@funding.vout}",
          amount_sats: @funding.escrow_sats
        },
        psbt_funding: funding_psbt_section,
        psbt_refund_timelock: refund_psbt_section,
        party_signing: {
          peg_party: party_signing_entry(@peg_party),
          investor: party_signing_entry(@investor)
        },
        oracle_policy: { feeds: ["admin_market_rate"], median: true }
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    private

    def funding_psbt_section
      if @funding.respond_to?(:funding_psbt) && @funding.funding_psbt.present?
        { psbt: @funding.funding_psbt, txid: @funding.txid, mode: "§3.2 async PSBT" }
      else
        { txid: @funding.txid, mode: "integration harness" }
      end
    end

    def refund_psbt_section
      base = {
        locktime_height: refund_locktime_height,
        note: "Path B — peg + investor 2-of-2 dopo refund_delay_blocks"
      }
      return base.merge(hex: nil, complete: false) unless @refund_psbt

      base.merge(
        hex: @refund_psbt[:hex],
        complete: @refund_psbt[:complete],
        peg_sats: @refund_psbt[:peg_sats],
        investor_sats: @refund_psbt[:investor_sats]
      )
    end

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

    def party_signing_entry(party)
      {
        public_key_hex: pubkey(party),
        wif: party_signing_wif(party)
      }
    end

    def party_signing_wif(party)
      return party.wif if party.respond_to?(:wif) && party.wif.present?
      return party.wif_for_signing if party.respond_to?(:wif_for_signing) && party.wif_for_signing.present?

      nil
    end
  end
end
