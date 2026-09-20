# frozen_string_literal: true

module L1
  # Validates a commitment PSBT used as proof-of-funds / anti-spam for anonymous
  # top-up create. Does not broadcast — only checks decode + unspent outpoints.
  class CommitmentPsbtValidator
    class Error < StandardError; end

    MAX_PENDING_PER_ADDRESS = 3

    def self.call(psbt_base64:, required_sats:, funding_address: nil)
      new(psbt_base64:, required_sats:, funding_address:).call
    end

    def initialize(psbt_base64:, required_sats:, funding_address: nil)
      @psbt_base64 = psbt_base64.to_s.strip
      @required_sats = required_sats.to_i
      @funding_address = funding_address.to_s.strip.presence
      @client = Bitcoind::Client.new
    end

    def call
      raise Error, "commitment_psbt required" if @psbt_base64.blank?
      raise Error, "required_sats must be positive" unless @required_sats.positive?

      decoded = decode_psbt!
      outpoints = extract_outpoints(decoded)
      raise Error, "commitment PSBT has no inputs" if outpoints.empty?

      total = 0
      outpoints.each do |op|
        assert_unspent!(op)
        assert_not_reserved!(op)
        total += op.fetch(:amount_sats)
      end

      if total < @required_sats
        raise Error, "commitment inputs insufficient (#{total} < #{@required_sats} sats)"
      end

      assert_address_rate_limit! if @funding_address

      outpoints
    end

    private

    def decode_psbt!
      @client.call("decodepsbt", @psbt_base64)
    rescue Bitcoind::Error => e
      raise Error, "invalid commitment PSBT: #{e.message}"
    end

    def extract_outpoints(decoded)
      tx = decoded.fetch("tx")
      inputs = decoded.fetch("inputs")
      vin = tx.fetch("vin")

      vin.each_with_index.map do |input, idx|
        txid = input.fetch("txid")
        vout = input.fetch("vout")
        amount_sats = amount_from_psbt_input(inputs[idx]) || amount_from_chain(txid, vout)
        raise Error, "cannot determine amount for #{txid}:#{vout}" if amount_sats.nil?

        { txid: txid, vout: vout, amount_sats: amount_sats }
      end
    end

    def amount_from_psbt_input(psbt_input)
      return if psbt_input.blank?

      witness = psbt_input["witness_utxo"]
      if witness && witness["amount"]
        return (witness["amount"].to_d * 100_000_000).to_i
      end

      non_witness = psbt_input["non_witness_utxo"]
      return unless non_witness.is_a?(Hash)

      # Prefer witness_utxo; if only non_witness hex is present, fall back to chain.
      nil
    end

    def amount_from_chain(txid, vout)
      utxo = @client.call("gettxout", txid, vout)
      return if utxo.blank?

      (utxo.fetch("value").to_d * 100_000_000).to_i
    end

    def assert_unspent!(op)
      utxo = @client.call("gettxout", op[:txid], op[:vout])
      raise Error, "outpoint #{op[:txid]}:#{op[:vout]} is spent or unknown" if utxo.blank?
    end

    def assert_not_reserved!(op)
      key = "#{op[:txid]}:#{op[:vout]}"
      conflict = Budget.awaiting_investor.where.not(reserved_outpoints: nil).find do |budget|
        Array(budget.reserved_outpoints).any? { |r| "#{r['txid']}:#{r['vout']}" == key || "#{r[:txid]}:#{r[:vout]}" == key }
      end
      raise Error, "outpoint #{key} already reserved by another top-up" if conflict
    end

    def assert_address_rate_limit!
      count = Budget.awaiting_investor.where(funding_address: @funding_address).count
      return if count < MAX_PENDING_PER_ADDRESS

      raise Error, "too many pending top-ups for this address (max #{MAX_PENDING_PER_ADDRESS})"
    end
  end
end
