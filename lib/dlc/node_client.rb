# frozen_string_literal: true

require "net/http"
require "json"

module Dlc
  # REST client for the dlc-rs sidecar.
  #
  # The sidecar builds an unsigned 2-of-2 from client fund pubkeys and CET
  # payout addresses. Adaptor signatures live on the phones (or, in regtest,
  # on the sidecar when `auto_sign: true`). At maturity the watchtower
  # decrypts both adaptor sigs with the oracle attestation — no party keys.
  #
  # Endpoint contract:
  #   POST /contracts                      -> unsigned funding + sign_package
  #   GET  /contracts/:id                  -> status + sign_package
  #   POST /contracts/:id/adaptor_sigs     -> store one party's CET/refund sigs
  #   POST /contracts/:id/execute          -> CET from attestation + close package
  #   POST /contracts/:id/refund           -> pre-signed refund
  #   GET  /info                           -> { pubkey, network, watchtower }
  class NodeClient
    class Error < StandardError; end

    Contract = Data.define(:contract_id, :funding_txid, :funding_vout, :funding_address, :funding_tx_hex, :status, :sign_package, :direct_payout, :raw)
    Execution = Data.define(:cet_txid, :outcome, :peg_sats, :investor_sats, :raw)
    Refund = Data.define(:refund_txid, :raw)
    DistributionResult = Data.define(:txid, :payouts, :investor_payout_sats, :investor_payout_address, :raw)

    DEFAULT_READ_TIMEOUT = 60
    INFO_READ_TIMEOUT = 5

    attr_reader :base_url

    def self.default
      new(base_url: Config.node_url, token: Config.node_token)
    end

    def initialize(base_url:, token: nil)
      raise Error, "base_url mancante per NodeClient" if base_url.blank?

      @base_url = base_url.to_s.chomp("/")
      @token = token.presence
    end

    def available?
      info.present?
    rescue Error
      false
    end

    def info
      get("/info", read_timeout: INFO_READ_TIMEOUT)
    end

    # Fase 1: build the DLC (offer + accept + adaptor sigs) and return the
    # UNSIGNED 2-of-2 funding tx. The 2-of-2 FUND keys stay at the sidecar, but
    # the funding INPUTS are the users' real L1 reserve UTXOs (signed by Ruby)
    # and the CET payout/change scriptpubkeys point at real reserve/change
    # addresses. `payouts` is the FloorEUR schedule as an array of
    # { outcome:, peg_sats:, investor_sats: } points over the numeric domain.
    # `peg_inputs`/`investor_inputs` are [{ txid:, vout:, amount_sats: }].
    def create_contract(oracle_announcement:, payouts:, peg_collateral_sats:,
                        investor_collateral_sats:, refund_locktime:,
                        peg_inputs:, investor_inputs:, peg_change_address:,
                        investor_change_address:, investor_payout_address:,
                        peg_payout_address: nil, peg_fund_pubkey: nil,
                        investor_fund_pubkey: nil, auto_sign: false,
                        fee_rate: 5, contract_id: nil)
      body = {
        oracle_announcement: oracle_announcement,
        payouts: Array(payouts).map { |p| normalize_payout(p) },
        offer_collateral_sats: Integer(peg_collateral_sats),
        accept_collateral_sats: Integer(investor_collateral_sats),
        refund_locktime: Integer(refund_locktime),
        fee_rate_sats_vb: Integer(fee_rate),
        peg_inputs: Array(peg_inputs).map { |i| normalize_input(i) },
        investor_inputs: Array(investor_inputs).map { |i| normalize_input(i) },
        peg_change_address: peg_change_address,
        investor_change_address: investor_change_address,
        investor_payout_address: investor_payout_address,
        peg_payout_address: peg_payout_address.presence || investor_payout_address,
        auto_sign: auto_sign
      }
      body[:peg_fund_pubkey] = peg_fund_pubkey if peg_fund_pubkey.present?
      body[:investor_fund_pubkey] = investor_fund_pubkey if investor_fund_pubkey.present?
      body[:contract_id] = contract_id if contract_id
      build_contract(post("/contracts", body))
    end

    def submit_adaptor_sigs(contract_id:, role:, adaptor_sigs:, refund_sig:)
      post("/contracts/#{contract_id}/adaptor_sigs", {
        role: role,
        adaptor_sigs: Array(adaptor_sigs),
        refund_sig: refund_sig
      })
    end

    def contract(contract_id:)
      build_contract(get("/contracts/#{contract_id}"))
    end

    # Maturity: broadcast the CET unlocked by the oracle attestation.
    def execute_contract(contract_id:, attestation:, close_package: nil)
      payload = { attestation: attestation }
      payload.merge!(close_package) if close_package.present?
      raw = post("/contracts/#{contract_id}/execute", payload)
      Execution.new(
        cet_txid: raw["cet_txid"] || raw["txid"],
        outcome: raw["outcome"].nil? ? nil : Integer(raw["outcome"]),
        peg_sats: raw["peg_sats"]&.to_i,
        investor_sats: raw["investor_sats"]&.to_i,
        raw: raw
      )
    end

    # Timelocked fallback: broadcast the refund once refund_locktime is reached.
    def refund_contract(contract_id:, close_package: nil)
      raw = post("/contracts/#{contract_id}/refund", close_package.presence || {})
      Refund.new(refund_txid: raw["refund_txid"] || raw["txid"], raw: raw)
    end

    # Fan out the peg_pot released by the CET to the individual holders. PoC
    # baseline: one on-chain transaction with `payouts` = [{ address:, sats: }].
    # (The atomic LN/HODL variant is not available on the vendored node.)
    def distribute(contract_id:, payouts:, fee_rate: 5)
      raw = post("/contracts/#{contract_id}/distribute", {
        payouts: Array(payouts).map { |p| normalize_distribution(p) },
        fee_rate_sats_vb: Integer(fee_rate)
      })
      DistributionResult.new(
        txid: raw["txid"],
        payouts: Array(raw["payouts"]),
        investor_payout_sats: raw["investor_payout_sats"]&.to_i,
        investor_payout_address: raw["investor_payout_address"],
        raw: raw
      )
    end

    private

    def normalize_input(input)
      {
        txid: input[:txid] || input["txid"],
        vout: Integer(input[:vout] || input["vout"]),
        amount_sats: Integer(input[:amount_sats] || input["amount_sats"])
      }
    end

    def normalize_payout(point)
      {
        outcome: Integer(point[:outcome] || point["outcome"]),
        peg_sats: Integer(point[:peg_sats] || point["peg_sats"]),
        investor_sats: Integer(point[:investor_sats] || point["investor_sats"])
      }
    end

    def normalize_distribution(point)
      {
        address: point[:address] || point["address"],
        sats: Integer(point[:sats] || point["sats"])
      }
    end

    def build_contract(raw)
      h = raw.is_a?(Hash) ? raw : {}
      Contract.new(
        contract_id: h["contract_id"] || h["id"],
        funding_txid: h["funding_txid"],
        funding_vout: h["funding_vout"]&.to_i,
        funding_address: h["funding_address"],
        funding_tx_hex: h["funding_tx_hex"],
        status: h["status"],
        sign_package: h["sign_package"],
        direct_payout: h["direct_payout"] != false,
        raw: raw
      )
    end

    def get(path, read_timeout: DEFAULT_READ_TIMEOUT)
      request(:get, path, read_timeout: read_timeout)
    end

    def post(path, body = {}, read_timeout: DEFAULT_READ_TIMEOUT)
      request(:post, path, body, read_timeout: read_timeout)
    end

    def request(method, path, body = nil, read_timeout: DEFAULT_READ_TIMEOUT)
      uri = URI.parse("#{@base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 2
      http.read_timeout = read_timeout

      response =
        case method
        when :get
          http.get(uri.request_uri, headers)
        when :post
          http.post(uri.request_uri, JSON.generate(body || {}), headers)
        else
          raise Error, "unsupported method #{method}"
        end

      parse(response)
    rescue Errno::ECONNREFUSED, SocketError
      raise Error, "Nodo DLC irraggiungibile a #{@base_url}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise Error, "Nodo DLC timeout a #{@base_url}"
    end

    def headers
      h = { "Content-Type" => "application/json" }
      h["Authorization"] = "Bearer #{@token}" if @token
      h
    end

    def parse(response)
      body = response.body.to_s
      parsed = body.empty? ? {} : JSON.parse(body)
      return parsed if response.is_a?(Net::HTTPSuccess)

      raise Error, error_detail(parsed) || "Nodo DLC error #{response.code}"
    rescue JSON::ParserError
      snippet = response.body.to_s.strip[0, 200]
      raise Error, "Nodo DLC error #{response.code}: #{snippet.presence || 'invalid JSON'}"
    end

    def error_detail(parsed)
      return unless parsed.is_a?(Hash)

      parsed["error"] || parsed["detail"] || parsed["message"]
    end
  end
end
