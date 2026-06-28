# frozen_string_literal: true

require "net/http"
require "json"

module Dlc
  # REST client for a DLC oracle (Kormir / Mycelia Signal).
  #
  # Lifecycle for a FloorEUR deal:
  #   * activation  -> #announce_numeric: the oracle commits to attest the
  #                    maturity price as a numeric (per-digit) event and returns
  #                    an OracleAnnouncement (one nonce per digit). The
  #                    announcement is embedded in the DLC contract.
  #   * maturity    -> #attest_numeric: the oracle reveals an OracleAttestation
  #                    (one signature per digit) that unlocks exactly one CET.
  #
  # The client speaks the Kormir HTTP server contract. Responses carry the
  # dlcspec objects hex-encoded plus structured fields; we expose both the raw
  # payload and parsed value objects so the DLC node layer (B.2) can forward the
  # hex blobs untouched while Ruby reasons over the structured view.
  class OracleClient
    class Error < StandardError; end

    # Structured view of an OracleAnnouncement (numeric event).
    Announcement = Data.define(
      :event_id, :oracle_pubkey, :nonces, :num_digits, :unit, :precision,
      :maturity_epoch, :hex, :raw
    )

    # Structured view of an OracleAttestation (numeric event).
    Attestation = Data.define(
      :event_id, :oracle_pubkey, :outcome, :digits, :signatures, :hex, :raw
    )

    DEFAULT_READ_TIMEOUT = 20
    HEALTH_READ_TIMEOUT = 5

    attr_reader :base_url

    def self.default
      new(base_url: Config.oracle_url, token: Config.oracle_token)
    end

    def initialize(base_url:, token: nil)
      raise Error, "base_url mancante per OracleClient" if base_url.blank?

      @base_url = base_url.to_s.chomp("/")
      @token = token.presence
    end

    # True when the oracle answers with its public key.
    def available?
      oracle_pubkey.present?
    rescue Error
      false
    end

    # The oracle's Schnorr public key (hex), used to verify attestations.
    def oracle_pubkey
      res = get("/pubkey", read_timeout: HEALTH_READ_TIMEOUT)
      return res if res.is_a?(String)

      res["pubkey"] || res["oracle_public_key"]
    end

    # Activation: ask the oracle to announce a numeric (per-digit) event.
    def announce_numeric(event_id:, maturity_epoch:,
                         num_digits: Config.num_digits, unit: Config.price_unit,
                         precision: Config.price_precision, is_signed: false)
      raw = post("/create-numeric-event", {
        event_id: event_id,
        num_digits: Integer(num_digits),
        is_signed: is_signed,
        precision: Integer(precision),
        unit: unit,
        event_maturity_epoch: Integer(maturity_epoch)
      })
      build_announcement(raw, fallback_event_id: event_id)
    end

    # Fetch a previously created announcement.
    def announcement(event_id:)
      raw = get("/event/#{event_id}")
      build_announcement(raw, fallback_event_id: event_id)
    end

    # Maturity: ask the oracle to attest the observed numeric outcome.
    # `maturity_epoch` is accepted for interface parity with PythiaOracleClient
    # (Kormir identifies the event by id alone) and otherwise ignored.
    def attest_numeric(event_id:, outcome:, maturity_epoch: nil)
      raw = post("/sign-numeric-event", {
        event_id: event_id,
        outcome: Integer(outcome)
      })
      build_attestation(raw, fallback_event_id: event_id)
    end

    # Fetch an attestation if the event has already been signed; nil otherwise.
    def attestation(event_id:)
      raw = get("/event/#{event_id}")
      return nil unless signed?(raw)

      build_attestation(raw, fallback_event_id: event_id)
    end

    private

    def signed?(raw)
      raw.is_a?(Hash) && (raw["attestation"].present? || raw["signatures"].present?)
    end

    def build_announcement(raw, fallback_event_id:)
      h = raw.is_a?(Hash) ? raw : {}

      Announcement.new(
        event_id: h.fetch("event_id", fallback_event_id),
        oracle_pubkey: h["oracle_public_key"] || h["oracle_pubkey"],
        nonces: Array(h["oracle_nonces"] || h["nonces"]),
        num_digits: h["num_digits"]&.to_i,
        unit: h["unit"],
        precision: h["precision"]&.to_i,
        maturity_epoch: (h["event_maturity_epoch"] || h["maturity_epoch"])&.to_i,
        hex: h["announcement"],
        raw: raw
      )
    end

    def build_attestation(raw, fallback_event_id:)
      h = raw.is_a?(Hash) ? raw : {}
      outcome = h["outcome"]

      Attestation.new(
        event_id: h.fetch("event_id", fallback_event_id),
        oracle_pubkey: h["oracle_public_key"] || h["oracle_pubkey"],
        outcome: outcome.nil? ? nil : Integer(outcome),
        digits: h["outcome_digits"]&.map { |d| Integer(d) },
        signatures: Array(h["signatures"]),
        hex: h["attestation"],
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
      raise Error, "Oracle DLC irraggiungibile a #{@base_url}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise Error, "Oracle DLC timeout a #{@base_url}"
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

      raise Error, error_detail(parsed) || "Oracle DLC error #{response.code}"
    rescue JSON::ParserError
      snippet = response.body.to_s.strip[0, 200]
      raise Error, "Oracle DLC error #{response.code}: #{snippet.presence || 'invalid JSON'}"
    end

    def error_detail(parsed)
      return unless parsed.is_a?(Hash)

      parsed["error"] || parsed["detail"] || parsed["message"]
    end
  end
end
