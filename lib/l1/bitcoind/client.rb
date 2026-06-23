# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module L1
  module Bitcoind
    class Error < StandardError; end

    class Client
      DEFAULT_URL = "http://regtest:regtest@127.0.0.1:18443"

      GLOBAL_METHODS = %w[
        createwallet
        listwallets
        loadwallet
        unloadwallet
        getblockchaininfo
        createrawtransaction
        signrawtransactionwithkey
        sendrawtransaction
        createmultisig
        getrawtransaction
        decodepsbt
        decoderawtransaction
        deriveaddresses
        getdescriptorinfo
        getaddressinfo
      ].freeze

      def initialize(url: ENV.fetch("BITCOIND_RPC_URL", DEFAULT_URL), wallet: nil)
        @root_uri = URI(url)
        @root_uri.path = "" if @root_uri.path.start_with?("/wallet/")
        @wallet = wallet
        @request_id = 0
      end

      def with_wallet(name)
        wallet_uri = @root_uri.dup
        wallet_uri.path = "/wallet/#{name}"
        self.class.new(url: wallet_uri.to_s, wallet: name)
      end

      def call(method, *params)
        @request_id += 1
        payload = {
          jsonrpc: "1.0",
          id: @request_id,
          method: method.to_s,
          params: params
        }

        response = post(rpc_uri(method), payload)
        raise Error, response["error"].inspect if response["error"]

        response["result"]
      end

      def available?
        call("getblockchaininfo")
        true
      rescue Error, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout
        false
      end

      private

      def rpc_uri(method)
        return @root_uri if @wallet.nil? || GLOBAL_METHODS.include?(method.to_s)

        uri = @root_uri.dup
        uri.path = "/wallet/#{@wallet}"
        uri
      end

      def post(uri, payload)
        request = Net::HTTP::Post.new(uri)
        request.basic_auth(uri.user, uri.password) if uri.user
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 5
        http.read_timeout = 120
        response = http.request(request)
        raise Error, "HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    end
  end
end
