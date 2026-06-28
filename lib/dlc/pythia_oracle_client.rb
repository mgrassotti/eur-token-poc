# frozen_string_literal: true

require "net/http"
require "json"
require "time"

module Dlc
  # REST client for the Pythia DLC oracle (https://github.com/dlc-markets/pythia,
  # a fork of sibyls). Pythia is a price-feed oracle: numeric (digit
  # decomposition) events are identified by `(asset_pair, maturity)` rather than
  # by an arbitrary event id, and announcements are produced ahead of time by a
  # cron scheduler. Its `eventId` has the form `{asset_pair}{unix_maturity}`.
  #
  # It is interface-compatible with Dlc::OracleClient so the contract/settlement
  # services can stay oracle-agnostic:
  #   * #announce_numeric -> GET the scheduled announcement for the maturity.
  #   * #attest_numeric   -> POST /force (debug mode) to attest the existing
  #                          announcement with the observed price, reusing its
  #                          committed nonces.
  #
  # Pythia returns the rust-dlc OracleAnnouncement / OracleAttestation as JSON
  # (not a hex TLV blob), so we forward the JSON object as a string in `#hex` for
  # the DLC node shim, which rebuilds the dlcspec messages from it.
  class PythiaOracleClient
    # Subclass of OracleClient::Error so existing `rescue OracleClient::Error`
    # in the services also catches Pythia failures.
    class Error < OracleClient::Error; end

    Announcement = OracleClient::Announcement
    Attestation = OracleClient::Attestation

    DEFAULT_READ_TIMEOUT = 20
    HEALTH_READ_TIMEOUT = 5
    # Number of times #announce_numeric polls for a scheduled announcement.
    ANNOUNCE_POLL_ATTEMPTS = 10
    ANNOUNCE_POLL_INTERVAL = 1.0

    attr_reader :base_url, :asset_pair, :version

    def self.default
      new(
        base_url: Config.oracle_url,
        asset_pair: Config.oracle_asset_pair,
        version: Config.oracle_version,
        base: Config.base
      )
    end

    def initialize(base_url:, asset_pair: "btc_usd", version: "v1", base: 2)
      raise Error, "base_url mancante per PythiaOracleClient" if base_url.blank?

      @base_url = base_url.to_s.chomp("/")
      @asset_pair = asset_pair.to_s
      @version = version.to_s.delete_prefix("/")
      @base = Integer(base)
    end

    # True when the oracle answers with its public key.
    def available?
      oracle_pubkey.present?
    rescue Error
      false
    end

    # The oracle's Schnorr public key (hex, x-only).
    def oracle_pubkey
      res = get("/#{version}/oracle/publickey", read_timeout: HEALTH_READ_TIMEOUT)
      return res if res.is_a?(String)

      res["publicKey"] || res["public_key"] || res["pubkey"]
    end

    # Activation: obtain the announcement Pythia scheduled for `maturity_epoch`.
    # `event_id` is accepted for interface parity but ignored — Pythia derives
    # the event id from the asset pair and maturity. Polls briefly because the
    # scheduler may not have published the announcement yet.
    def announce_numeric(maturity_epoch:, event_id: nil, **_opts)
      ann = nil
      ANNOUNCE_POLL_ATTEMPTS.times do |i|
        ann = fetch_announcement(maturity_epoch)
        break if ann

        sleep(ANNOUNCE_POLL_INTERVAL) if i < ANNOUNCE_POLL_ATTEMPTS - 1
      end
      raise Error, "Pythia: nessun announcement per maturity #{maturity_epoch} (#{rfc3339(maturity_epoch)})" if ann.nil?

      build_announcement(ann, maturity_epoch)
    end

    # Fetch a previously created announcement, or nil if not yet scheduled.
    def announcement(maturity_epoch:, **_opts)
      ann = fetch_announcement(maturity_epoch)
      ann && build_announcement(ann, maturity_epoch)
    end

    # Maturity: force the oracle to attest `outcome` for the announcement at
    # `maturity_epoch` (debug mode). Pythia reuses the announcement's committed
    # nonces, so the attestation unlocks the CET bound at activation.
    def attest_numeric(outcome:, maturity_epoch:, event_id: nil, **_opts)
      res = post("/#{version}/force", {
        maturation: rfc3339(maturity_epoch),
        price: Integer(outcome)
      })
      build_attestation(res, maturity_epoch)
    end

    # Fetch an attestation if the event has already been attested; nil otherwise.
    def attestation(maturity_epoch:, **_opts)
      res = get_optional("/#{version}/asset/#{asset_pair}/attestation/#{rfc3339(maturity_epoch)}")
      return nil if res.nil?

      build_attestation({ "attestation" => res }, maturity_epoch)
    end

    private

    attr_reader :base

    def fetch_announcement(maturity_epoch)
      get_optional("/#{version}/asset/#{asset_pair}/announcement/#{rfc3339(maturity_epoch)}")
    end

    def build_announcement(ann, fallback_maturity)
      event = ann["oracleEvent"] || {}
      descriptor = dig_descriptor(event)

      Announcement.new(
        event_id: event["eventId"] || "#{asset_pair}#{fallback_maturity}",
        oracle_pubkey: ann["oraclePublicKey"],
        nonces: Array(event["oracleNonces"]),
        num_digits: descriptor["nbDigits"]&.to_i,
        unit: descriptor["unit"],
        precision: descriptor["precision"]&.to_i,
        maturity_epoch: (event["eventMaturityEpoch"] || fallback_maturity)&.to_i,
        hex: JSON.generate(ann),
        raw: ann
      )
    end

    def build_attestation(res, fallback_maturity)
      att = res["attestation"] || res
      announcement = res["announcement"]
      values = Array(att["values"])
      digits = values.map { |v| Integer(v) }

      Attestation.new(
        event_id: att["eventId"] || (announcement && announcement.dig("oracleEvent", "eventId")) ||
          "#{asset_pair}#{fallback_maturity}",
        oracle_pubkey: announcement && announcement["oraclePublicKey"],
        outcome: digits.empty? ? nil : digits_to_integer(digits),
        digits: digits.presence,
        signatures: Array(att["signatures"]),
        hex: JSON.generate(att),
        raw: res
      )
    end

    def dig_descriptor(event)
      descriptor = event["eventDescriptor"] || {}
      descriptor["digitDecompositionEvent"] || descriptor["digit_decomposition_event"] || descriptor
    end

    def digits_to_integer(digits)
      digits.reduce(0) { |acc, d| (acc * base) + d }
    end

    def rfc3339(epoch)
      Time.at(Integer(epoch)).utc.iso8601
    end

    def get(path, read_timeout: DEFAULT_READ_TIMEOUT)
      request(:get, path, read_timeout: read_timeout)
    end

    # GET that returns nil on a 404/425 (event not announced/attested yet)
    # instead of raising.
    def get_optional(path, read_timeout: DEFAULT_READ_TIMEOUT)
      request(:get, path, read_timeout: read_timeout, optional: true)
    end

    def post(path, body = {}, read_timeout: DEFAULT_READ_TIMEOUT)
      request(:post, path, body, read_timeout: read_timeout)
    end

    def request(method, path, body = nil, read_timeout: DEFAULT_READ_TIMEOUT, optional: false)
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

      parse(response, optional: optional)
    rescue Errno::ECONNREFUSED, SocketError
      raise Error, "Oracle Pythia irraggiungibile a #{@base_url}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise Error, "Oracle Pythia timeout a #{@base_url}"
    end

    def headers
      { "Content-Type" => "application/json" }
    end

    def parse(response, optional: false)
      return nil if optional && !response.is_a?(Net::HTTPSuccess)

      body = response.body.to_s
      parsed = body.empty? ? {} : JSON.parse(body)
      return parsed if response.is_a?(Net::HTTPSuccess)

      raise Error, error_detail(parsed) || "Oracle Pythia error #{response.code}"
    rescue JSON::ParserError
      return nil if optional

      snippet = response.body.to_s.strip[0, 200]
      raise Error, "Oracle Pythia error #{response.code}: #{snippet.presence || 'invalid JSON'}"
    end

    def error_detail(parsed)
      return unless parsed.is_a?(Hash)

      parsed["error"] || parsed["detail"] || parsed["message"]
    end
  end
end
