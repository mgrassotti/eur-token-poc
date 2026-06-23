# frozen_string_literal: true

module L1
  # §3.2 PSBT asincrona: peg + investor aggiungono input e firmano prima del broadcast.
  # Nessun deposito parziale on-chain (§3.3 escluso dal piano).
  class FundingPsbtService
    class Error < StandardError; end

    ESTIMATED_FEE_SATS = 5_000

    def self.call(budget:)
      new(budget:).call
    end

    def initialize(budget:)
      @budget = budget
      @global_client = Bitcoind::Client.new
      @bot = BotKey.generate
    end

    def call
      validate!

      peg_wallet = UserWallet.for(budget.borrower)
      investor_wallet = UserWallet.for(budget.investor)
      peg_party = wallet_party(peg_wallet, :peg_party)
      investor_party = wallet_party(investor_wallet, :investor)

      escrow = Escrow.from_keys(
        peg_party: peg_party,
        investor: investor_party,
        bot: @bot,
        client: @global_client
      )

      peg_sats = budget.borrower_locked_sats
      investor_sats = budget.investor_locked_sats
      escrow_sats = peg_sats + investor_sats

      validate_on_chain_balances!(peg_wallet, investor_wallet, peg_sats, investor_sats)

      signed_tx = build_and_sign_psbt!(
        peg_wallet: peg_wallet,
        investor_wallet: investor_wallet,
        escrow: escrow,
        escrow_sats: escrow_sats,
        peg_sats: peg_sats,
        investor_sats: investor_sats
      )

      txid = @global_client.call("sendrawtransaction", signed_tx.fetch(:hex))
      confirm_regtest_block!

      RegtestHarness::FundingResult.new(
        txid: txid,
        vout: 0,
        escrow_sats: escrow_sats,
        peg_sats: peg_sats,
        investor_sats: investor_sats,
        peg_party: peg_party,
        investor: investor_party,
        bot: @bot,
        escrow: escrow,
        funding_psbt: signed_tx.fetch(:psbt)
      )
    end

    private

    attr_reader :budget

    def validate!
      raise Error, "Budget is not active" unless budget.active?
      raise Error, "Investitore mancante" unless budget.investor_id
      raise Error, "Collateral borrower non impostato" unless budget.borrower_locked_sats.positive?
      raise Error, "Collateral investitore non impostato" unless budget.investor_locked_sats.positive?
    end

    def wallet_party(wallet, label)
      WalletParty.new(
        label: label,
        public_key_hex: wallet.identity_pubkey,
        wif: wallet.escrow_identity_wif
      )
    end

    def validate_on_chain_balances!(peg_wallet, investor_wallet, peg_sats, investor_sats)
      if peg_wallet.spendable_sats < peg_sats
        raise Error,
              "Saldo on-chain insufficiente per #{peg_wallet.wallet_name} " \
              "(#{peg_wallet.spendable_sats} < #{peg_sats} sats). Deposita sul conto riserva."
      end

      required_investor = investor_sats + ESTIMATED_FEE_SATS
      return if investor_wallet.spendable_sats >= required_investor

      raise Error,
            "Saldo on-chain insufficiente per #{investor_wallet.wallet_name} " \
            "(#{investor_wallet.spendable_sats} < #{required_investor} sats). Deposita sul conto riserva."
    end

    def build_and_sign_psbt!(peg_wallet:, investor_wallet:, escrow:, escrow_sats:, peg_sats:, investor_sats:)
      peg_coins = peg_wallet.select_coins(peg_sats)
      inv_coins = investor_wallet.select_coins(investor_sats + ESTIMATED_FEE_SATS)
      inputs = (peg_coins + inv_coins).map { |coin| { "txid" => coin.fetch("txid"), "vout" => coin.fetch("vout") } }

      peg_input_sats = coin_sum_sats(peg_coins)
      inv_input_sats = coin_sum_sats(inv_coins)
      fee_sats = ESTIMATED_FEE_SATS
      peg_change_sats = peg_input_sats - peg_sats
      inv_change_sats = inv_input_sats - investor_sats - fee_sats
      raise Error, "UTXO borrower insufficienti per la fee di rete" if peg_change_sats.negative?
      raise Error, "UTXO investitore insufficienti per collateral + fee" if inv_change_sats.negative?

      outputs = [{ escrow.address => btc(escrow_sats) }]
      outputs << { peg_wallet.change_address => btc(peg_change_sats) } if peg_change_sats.positive?
      outputs << { investor_wallet.change_address => btc(inv_change_sats) } if inv_change_sats.positive?

      raw = @global_client.call("createrawtransaction", inputs, outputs)
      signed = peg_wallet.client.call("signrawtransactionwithwallet", raw)
      signed = investor_wallet.client.call("signrawtransactionwithwallet", signed.fetch("hex"))
      raise Error, "Funding tx incompleta" unless signed.fetch("complete")

      hex = signed.fetch("hex")
      psbt = @global_client.call("converttopsbt", hex, true)

      { psbt: psbt, hex: hex }
    end

    def coin_sum_sats(coins)
      coins.sum { |coin| (coin.fetch("amount").to_d * 100_000_000).to_i }
    end

    def btc(sats)
      format("%.8f", sats / 100_000_000.0)
    end

    def confirm_regtest_block!
      RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET).mine_blocks(1)
    end
  end
end
