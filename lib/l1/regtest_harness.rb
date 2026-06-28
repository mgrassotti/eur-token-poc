# frozen_string_literal: true

module L1
  # High-level regtest orchestration for M1 integration tests.
  class RegtestHarness
    FundingResult = Data.define(
      :txid,
      :vout,
      :escrow_sats,
      :peg_sats,
      :investor_sats,
      :peg_party,
      :investor,
      :bot,
      :escrow,
      :funding_psbt
    )

    SettlementResult = Data.define(:txid, :holder_sats, :investor_sats)

    PartyKey = Data.define(:label, :address, :wif, :public_key_hex) do
      def wif_for_signing = wif
    end

    attr_reader :global_client, :client, :peg_party, :investor, :bot, :escrow, :wallet_name

    COINBASE_MATURITY_BLOCKS = 101

    def initialize(client: Bitcoind::Client.new, wallet_name: SHARED_REGTEST_WALLET)
      @global_client = client
      @wallet_name = wallet_name
      ensure_wallet!
      @client = @global_client.with_wallet(wallet_name)
      @peg_party = load_party_key("peg_party")
      @investor = load_party_key("investor")
      @bot = load_party_key("bot")
      @escrow = Escrow.from_keys(peg_party: @peg_party, investor: @investor, bot: @bot, client: @global_client)
    end

    def self.with_available_bitcoind
      global = Bitcoind::Client.new
      return unless global.available?

      harness = new(client: global)
      harness.ensure_chain_ready!
      yield harness
    end

    def ensure_chain_ready!
      info = @global_client.call("getblockchaininfo")
      return if info.fetch("blocks").to_i >= 101

      mine_blocks(101)
    end

    FUNDING_FEE_BUFFER_SATS = 10_000
    ESTIMATED_TX_FEE_SATS = 1_000

    # Integration-test shortcut: atomic funding tx (not §3.3 sequential deposit).
    def fund_escrow!(peg_sats:, investor_sats:)
      required_wallet_sats = peg_sats + investor_sats + (2 * FUNDING_FEE_BUFFER_SATS) + (3 * ESTIMATED_TX_FEE_SATS)
      ensure_spendable_balance!(required_wallet_sats)

      peg_utxo = fund_party!(peg_party, peg_sats + FUNDING_FEE_BUFFER_SATS)
      investor_utxo = fund_party!(investor, investor_sats + FUNDING_FEE_BUFFER_SATS)
      escrow_sats = peg_sats + investor_sats
      total_in = peg_utxo.value_sats + investor_utxo.value_sats
      change_sats = total_in - escrow_sats - ESTIMATED_TX_FEE_SATS
      raise Bitcoind::Error, "Insufficient sats for funding tx fee" if change_sats.negative?

      outputs = [{ escrow.address => btc(escrow_sats) }]
      outputs << { peg_party.address => btc(change_sats) } if change_sats.positive?

      raw = @global_client.call(
        "createrawtransaction",
        [
          { txid: peg_utxo.txid, vout: peg_utxo.vout },
          { txid: investor_utxo.txid, vout: investor_utxo.vout }
        ],
        outputs
      )

      signed = sign_p2wpkh_inputs(
        raw,
        [
          [peg_utxo, peg_party],
          [investor_utxo, investor]
        ]
      )

      txid = @global_client.call("sendrawtransaction", signed)
      FundingResult.new(
        txid: txid,
        vout: 0,
        escrow_sats: escrow_sats,
        peg_sats: peg_sats,
        investor_sats: investor_sats,
        peg_party: peg_party,
        investor: investor,
        bot: bot,
        escrow: escrow,
        funding_psbt: nil
      )
    end

    def broadcast_refund!(signed_hex:, locktime_height:)
      decoded = @global_client.call("decoderawtransaction", signed_hex)
      raise Bitcoind::Error, "Refund before locktime" if current_height < locktime_height

      @global_client.call("sendrawtransaction", signed_hex)
    end

    def spend_escrow!(funding:, holder_sats:, investor_sats:, signers:)
      holder_address = new_address("holder")
      investor_address = new_address("investor_payout")

      outputs = []
      outputs << { holder_address => btc(holder_sats) } if holder_sats.positive?
      outputs << { investor_address => btc(investor_sats) } if investor_sats.positive?

      raw = @global_client.call(
        "createrawtransaction",
        [{ txid: funding.txid, vout: funding.vout }],
        outputs
      )

      signed = sign_escrow_spend(raw, funding: funding, signers: signers)
      raise Bitcoind::Error, "Expected complete 2-of-3 signatures" unless signed.fetch("complete")

      txid = @global_client.call("sendrawtransaction", signed.fetch("hex"))
      SettlementResult.new(txid: txid, holder_sats: holder_sats, investor_sats: investor_sats)
    end

    def incomplete_escrow_sign(funding:, signers:)
      holder_address = new_address("holder_probe")
      raw = @global_client.call(
        "createrawtransaction",
        [{ txid: funding.txid, vout: funding.vout }],
        [{ holder_address => btc(funding.escrow_sats - 10_000) }]
      )

      sign_escrow_spend(raw, funding: funding, signers: signers)
    end

    def build_refund_tx(funding:, peg_sats:, investor_sats:, locktime_height:)
      peg_address = peg_party.address
      investor_address = investor.address

      raw = @global_client.call(
        "createrawtransaction",
        [{ txid: funding.txid, vout: funding.vout, sequence: 0xfffffffe }],
        [
          { peg_address => btc(peg_sats) },
          { investor_address => btc(investor_sats) }
        ],
        locktime_height
      )

      sign_escrow_spend(raw, funding: funding, signers: [peg_party, investor])
    end

    def mine_blocks(count)
      address = new_address("miner")
      client.call("generatetoaddress", count, address)
    end

    # Sends regtest BTC from the shared wallet to an arbitrary address (e.g. an
    # RGB Lightning Node vanilla address) and confirms it. Used to fund RLN nodes
    # so they can create colorable UTXOs for RGB issuance/transfers.
    def fund_address!(address, sats:)
      ensure_spendable_balance!(sats + ESTIMATED_TX_FEE_SATS)
      txid = client.call("sendtoaddress", address, btc(sats))
      mine_blocks(1)
      txid
    end

    def current_height
      @global_client.call("getblockchaininfo").fetch("blocks")
    end

    private

    Utxo = Data.define(:txid, :vout, :value_sats, :script_pubkey_hex)

    def ensure_wallet!
      wallets = @global_client.call("listwallets")
      return if wallets.include?(wallet_name)

      @global_client.call("createwallet", wallet_name, false, false, "", false, true)
    rescue Bitcoind::Error => e
      raise unless e.message.include?("Database already exists") || e.message.include?("already exists")

      @global_client.call("loadwallet", wallet_name) unless @global_client.call("listwallets").include?(wallet_name)
    end

    def load_party_key(label)
      key = KeyMaterial.generate
      base_desc = "wpkh(#{key.public_key_hex})"
      descriptor = @global_client.call("getdescriptorinfo", base_desc).fetch("descriptor")
      address = @global_client.call("deriveaddresses", descriptor).first
      PartyKey.new(label: label, address: address, wif: key.wif, public_key_hex: key.public_key_hex)
    end

    def new_address(label)
      client.call("getnewaddress", label, "bech32")
    end

    def fund_party!(party, sats)
      ensure_spendable_balance!(sats + ESTIMATED_TX_FEE_SATS)

      txid = client.call("sendtoaddress", party.address, btc(sats))
      mine_blocks(1)

      decoded = client.call("getrawtransaction", txid, true)
      output = decoded.fetch("vout").find { |o| o.dig("scriptPubKey", "address") == party.address }
      raise Bitcoind::Error, "Funding output not found for #{party.label}" unless output

      Utxo.new(
        txid: txid,
        vout: output.fetch("n"),
        value_sats: sats_to_i(output.fetch("value")),
        script_pubkey_hex: output.dig("scriptPubKey", "hex")
      )
    end

    # Coinbase on a fresh wallet needs 100 confirmations before spend (regtest).
    def ensure_spendable_balance!(min_sats)
      return if spendable_sats >= min_sats

      mine_blocks(COINBASE_MATURITY_BLOCKS)

      return if spendable_sats >= min_sats

      raise Bitcoind::Error,
            "Saldo spendibile insufficiente nel wallet #{wallet_name} " \
            "(#{spendable_sats} < #{min_sats} sats). Riprova o ./bin/regtest down && ./bin/regtest up"
    end

    def spendable_sats
      sats_to_i(client.call("getbalance", "*", 1))
    end

    def sign_p2wpkh_inputs(raw, utxo_key_pairs)
      hex = raw
      utxo_key_pairs.each do |utxo, key|
        signed = client.call(
          "signrawtransactionwithkey",
          hex,
          [key.wif],
          [{
            txid: utxo.txid,
            vout: utxo.vout,
            scriptPubKey: utxo.script_pubkey_hex,
            amount: btc(utxo.value_sats)
          }]
        )
        hex = signed.fetch("hex")
      end
      hex
    end

    def sign_escrow_spend(raw, funding:, signers:)
      prev = escrow_prevout(funding)

      client.call("signrawtransactionwithkey", raw, signers.map(&:wif_for_signing), [prev])
    end

    def escrow_prevout(funding)
      tx = @global_client.call("getrawtransaction", funding.txid, true)
      output = tx.fetch("vout")[funding.vout]

      {
        txid: funding.txid,
        vout: funding.vout,
        scriptPubKey: output.dig("scriptPubKey", "hex"),
        redeemScript: escrow.redeem_script_hex,
        witnessScript: escrow.witness_script_hex,
        amount: btc(funding.escrow_sats)
      }
    end

    def btc(sats)
      format("%.8f", sats / 100_000_000.0)
    end

    def sats_to_i(btc_float)
      (btc_float.to_d * 100_000_000).to_i
    end
  end
end
