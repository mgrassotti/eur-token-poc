# frozen_string_literal: true

module L1
  # Verifies client-supplied UTXOs are unspent and sum to at least required_sats.
  class UtxoSetValidator
    class Error < StandardError; end

    def self.call(inputs:, required_sats:, label: "inputs")
      new(inputs:, required_sats:, label:).call
    end

    def initialize(inputs:, required_sats:, label: "inputs")
      @inputs = Array(inputs)
      @required_sats = required_sats.to_i
      @label = label
      @client = Bitcoind::Client.new
    end

    def call
      raise Error, "#{@label} required" if @inputs.empty?

      total = 0
      @inputs.each do |raw|
        op = normalize(raw)
        utxo = @client.call("gettxout", op[:txid], op[:vout])
        raise Error, "#{@label} outpoint #{op[:txid]}:#{op[:vout]} is spent or unknown" if utxo.blank?

        chain_sats = (utxo.fetch("value").to_d * 100_000_000).to_i
        if op[:amount_sats].positive? && op[:amount_sats] != chain_sats
          raise Error, "#{@label} amount mismatch for #{op[:txid]}:#{op[:vout]}"
        end

        total += chain_sats
      end

      return total if total >= @required_sats

      raise Error, "#{@label} insufficient (#{total} < #{@required_sats} sats)"
    end

    private

    def normalize(raw)
      h = raw.respond_to?(:deep_symbolize_keys) ? raw.deep_symbolize_keys : raw.to_h.symbolize_keys
      {
        txid: h.fetch(:txid).to_s,
        vout: h.fetch(:vout).to_i,
        amount_sats: h[:amount_sats].to_i
      }
    end
  end
end
