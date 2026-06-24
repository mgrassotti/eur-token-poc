# frozen_string_literal: true

require "net/http"
require "json"

module Rgb
  class SidecarClient
    class Error < StandardError; end

    def self.instance
      @instance ||= new
    end

    def initialize(base_url: Config.sidecar_url)
      @base_url = base_url.chomp("/")
      @last_check_at = nil
      @available = false
    end

    def available?
      return @available if @last_check_at && Time.current - @last_check_at < 5.seconds

      @last_check_at = Time.current
      @available = health["ok"] == true
    rescue Error
      @available = false
    end

    def health
      get("/health")
    end

    def create_wallet(wallet_id:, mnemonic: nil)
      post("/wallets", wallet_id: wallet_id, mnemonic: mnemonic)
    end

    def setup_wallet(wallet_id)
      post("/wallets/#{wallet_id}/setup", {})
    end

    def reset_all_wallets!
      post("/wallets/reset-all", {})
      @last_check_at = nil
      @available = false
    end

    def list_assets(wallet_id)
      get("/wallets/#{wallet_id}/assets")
    end

    def issue(wallet_id:, ticker:, name:, precision:, amounts:)
      post("/issue", wallet_id: wallet_id, ticker: ticker, name: name, precision: precision, amounts: amounts)
    end

    def blind_receive(wallet_id:, asset_id:, amount:)
      raise Error, "wallet_id mancante per blind_receive" if wallet_id.blank?

      post("/receive/blind", wallet_id: wallet_id, asset_id: asset_id, amount: amount)
    end

    def send_asset(sender_wallet_id:, recipient_wallet_id:, asset_id:, recipient_id:, amount:)
      raise Error, "sender_wallet_id mancante" if sender_wallet_id.blank?
      raise Error, "recipient_wallet_id mancante" if recipient_wallet_id.blank?

      post(
        "/send",
        sender_wallet_id: sender_wallet_id,
        recipient_wallet_id: recipient_wallet_id,
        asset_id: asset_id,
        recipient_id: recipient_id,
        amount: amount
      )
    end

    private

    def get(path)
      request(:get, path)
    end

    def post(path, body)
      request(:post, path, body)
    end

    def request(method, path, body = nil)
      uri = URI.parse("#{@base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 2
      http.read_timeout = 120

      response = case method
                 when :get
                   http.get(uri.request_uri)
                 when :post
                   http.post(uri.request_uri, JSON.generate(body), "Content-Type" => "application/json")
                 else
                   raise Error, "unsupported method #{method}"
                 end

      parsed = JSON.parse(response.body)
      return parsed if response.is_a?(Net::HTTPSuccess)

      raise Error, error_detail(parsed) || "RGB sidecar error #{response.code}"
    rescue JSON::ParserError
      snippet = response.body.to_s.strip[0, 200]
      raise Error, "RGB sidecar error #{response.code}: #{snippet.presence || 'invalid JSON'}"
    rescue Errno::ECONNREFUSED, SocketError
      raise Error, "RGB sidecar unreachable at #{@base_url}"
    end

    def error_detail(parsed)
      detail = parsed["detail"]
      case detail
      when Array
        detail.map { |entry| entry["msg"] || entry.to_s }.join("; ")
      when String
        detail
      end
    end
  end
end
