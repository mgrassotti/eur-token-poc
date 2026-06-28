# frozen_string_literal: true

require "net/http"
require "json"

module Rgb
  # REST client for a single RGB Lightning Node (RLN) instance.
  #
  # One instance targets one node (one URL per user/role). Unlike the legacy
  # Rgb::SidecarClient there is no wallet_id: the node *is* the wallet. Auth is
  # optional (nodes started with --disable-authentication need no token); a
  # Biscuit bearer token may be supplied for hardened deployments.
  #
  # Endpoint shapes follow the RGB Lightning Node OpenAPI (master). RGB fungible
  # quantities are expressed via an Assignment object: {type: "Fungible", value: N}.
  class LightningClient
    class Error < StandardError; end

    DEFAULT_READ_TIMEOUT = 120
    DASHBOARD_READ_TIMEOUT = 5

    attr_reader :base_url

    def initialize(base_url:, token: nil)
      raise Error, "base_url mancante per LightningClient" if base_url.blank?

      @base_url = base_url.to_s.chomp("/")
      @token = token.presence
      @last_check_at = nil
      @available = false
    end

    # --- Node lifecycle ---------------------------------------------------

    def available?
      return @available if @last_check_at && Time.current - @last_check_at < 5.seconds

      @last_check_at = Time.current
      node_info(read_timeout: DASHBOARD_READ_TIMEOUT)
      @available = true
    rescue Error
      @available = false
    end

    # Returns the BIP39 mnemonic. Idempotency is the caller's concern: a node
    # that is already initialized returns an error which callers may ignore.
    def init(password:)
      post("/init", { password: password })
    end

    def unlock(password:, bitcoind_rpc_username:, bitcoind_rpc_password:,
               bitcoind_rpc_host:, bitcoind_rpc_port:, indexer_url:, proxy_endpoint:,
               announce_addresses: [], announce_alias: nil)
      body = {
        password: password,
        bitcoind_rpc_username: bitcoind_rpc_username,
        bitcoind_rpc_password: bitcoind_rpc_password,
        bitcoind_rpc_host: bitcoind_rpc_host,
        bitcoind_rpc_port: bitcoind_rpc_port,
        indexer_url: indexer_url,
        proxy_endpoint: proxy_endpoint,
        announce_addresses: Array(announce_addresses)
      }
      body[:announce_alias] = announce_alias if announce_alias
      post("/unlock", body)
    end

    def lock
      post("/lock")
    end

    def node_info(read_timeout: DEFAULT_READ_TIMEOUT)
      get("/nodeinfo", read_timeout: read_timeout)
    end

    def node_pubkey
      node_info["pubkey"]
    end

    # --- On-chain BTC -----------------------------------------------------

    def address
      post("/address")
    end

    def btc_balance(skip_sync: false)
      post("/btcbalance", { skip_sync: skip_sync })
    end

    def create_utxos(num: 4, size: 32_500, fee_rate: 5, up_to: false, skip_sync: false)
      post("/createutxos", {
        up_to: up_to,
        num: num,
        size: size,
        fee_rate: fee_rate,
        skip_sync: skip_sync
      })
    end

    # --- RGB assets -------------------------------------------------------

    def issue_asset_nia(ticker:, name:, precision:, amounts:)
      post("/issueassetnia", {
        ticker: ticker,
        name: name,
        precision: precision,
        amounts: Array(amounts)
      })
    end

    def list_assets
      post("/listassets")
    end

    def asset_balance(asset_id:, read_timeout: DEFAULT_READ_TIMEOUT)
      post("/assetbalance", { asset_id: asset_id }, read_timeout: read_timeout)
    end

    # Recipient side: produce a blinded invoice for an incoming transfer.
    def rgb_invoice(asset_id:, amount:, min_confirmations: 1, witness: false)
      post("/rgbinvoice", {
        asset_id: asset_id,
        assignment: fungible(amount),
        min_confirmations: min_confirmations,
        witness: witness
      })
    end

    def decode_rgb_invoice(invoice:)
      post("/decodergbinvoice", { invoice: invoice })
    end

    # Sender side: pay an RGB recipient_id (blinded UTXO) on-chain via /sendrgb.
    # The recipient_map is keyed by asset_id; each entry is a Recipient.
    def send_asset(asset_id:, amount:, recipient_id:, transport_endpoints:,
                   fee_rate: 5, min_confirmations: 1, donation: false)
      post("/sendrgb", {
        donation: donation,
        fee_rate: fee_rate,
        min_confirmations: min_confirmations,
        recipient_map: {
          asset_id => [
            {
              recipient_id: recipient_id,
              assignment: fungible(amount),
              transport_endpoints: Array(transport_endpoints)
            }
          ]
        }
      })
    end

    def refresh_transfers(skip_sync: false)
      post("/refreshtransfers", { filter: [], skip_sync: skip_sync })
    end

    # --- Lightning --------------------------------------------------------

    def connect_peer(peer_pubkey_and_addr:)
      post("/connectpeer", { peer_pubkey_and_addr: peer_pubkey_and_addr })
    end

    def open_channel(peer_pubkey_and_opt_addr:, capacity_sat:, asset_id: nil, asset_amount: nil)
      body = { peer_pubkey_and_opt_addr: peer_pubkey_and_opt_addr, capacity_sat: capacity_sat }
      body[:asset_id] = asset_id if asset_id
      body[:asset_amount] = asset_amount if asset_amount
      post("/openchannel", body)
    end

    def list_channels
      get("/listchannels")
    end

    def ln_invoice(amt_msat: nil, asset_id: nil, asset_amount: nil, expiry_sec: 420)
      body = { expiry_sec: expiry_sec }
      body[:amt_msat] = amt_msat if amt_msat
      body[:asset_id] = asset_id if asset_id
      body[:asset_amount] = asset_amount if asset_amount
      post("/lninvoice", body)
    end

    def send_payment(invoice:)
      post("/sendpayment", { invoice: invoice })
    end

    def keysend(dest_pubkey:, amt_msat: nil, asset_id: nil, asset_amount: nil)
      body = { dest_pubkey: dest_pubkey }
      body[:amt_msat] = amt_msat if amt_msat
      body[:asset_id] = asset_id if asset_id
      body[:asset_amount] = asset_amount if asset_amount
      post("/keysend", body)
    end

    # --- HODL invoices (atomicity hooks for DLC distribution) -------------
    #
    # NOTE: the vendored RGB-Tools node does not expose these endpoints; they
    # require a newer build (e.g. the RGB-OS fork). Kept for the B.3 atomic
    # distribution workstream; calls will 404 against the current submodule.

    # payment_hash lets the caller bind settlement to an externally-known secret
    # (e.g. the oracle attestation), enabling best-effort atomic payout.
    def hodl_invoice(payment_hash:, expiry_sec: 86_400, amt_msat: nil, asset_id: nil, asset_amount: nil, external_ref: nil)
      body = { payment_hash: payment_hash, expiry_sec: expiry_sec }
      body[:amt_msat] = amt_msat if amt_msat
      body[:asset_id] = asset_id if asset_id
      body[:asset_amount] = asset_amount if asset_amount
      body[:external_ref] = external_ref if external_ref
      post("/hodlinvoice", body)
    end

    def settle_hodl_invoice(payment_hash:, payment_preimage:)
      post("/settlehodlinvoice", { payment_hash: payment_hash, payment_preimage: payment_preimage })
    end

    def cancel_hodl_invoice(payment_hash:)
      post("/cancelhodlinvoice", { payment_hash: payment_hash })
    end

    def invoice_status(invoice:)
      post("/invoicestatus", { invoice: invoice })
    end

    private

    def fungible(amount)
      { type: "Fungible", value: Integer(amount) }
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
      raise Error, "RLN node unreachable at #{@base_url}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise Error, "RLN node timeout at #{@base_url}"
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

      raise Error, error_detail(parsed) || "RLN node error #{response.code}"
    rescue JSON::ParserError
      snippet = response.body.to_s.strip[0, 200]
      raise Error, "RLN node error #{response.code}: #{snippet.presence || 'invalid JSON'}"
    end

    def error_detail(parsed)
      return unless parsed.is_a?(Hash)

      parsed["error"] || parsed["detail"] || parsed["name"]
    end
  end
end
