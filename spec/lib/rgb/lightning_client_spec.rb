# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rgb::LightningClient do
  subject(:client) { described_class.new(base_url: "http://node.test:3001") }

  # Minimal Net::HTTP fake: records the last request and returns a canned body.
  let(:http) { instance_spy("Net::HTTP") }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
  end

  def ok(json)
    res = Net::HTTPOK.new("1.1", "200", "OK")
    res.instance_variable_set(:@body, JSON.generate(json))
    res.instance_variable_set(:@read, true)
    res
  end

  def bad(json, code = "400")
    res = Net::HTTPBadRequest.new("1.1", code, "Bad Request")
    res.instance_variable_set(:@body, JSON.generate(json))
    res.instance_variable_set(:@read, true)
    res
  end

  it "builds an absolute URL from base_url" do
    expect(client.base_url).to eq("http://node.test:3001")
  end

  it "raises without a base_url" do
    expect { described_class.new(base_url: "") }.to raise_error(described_class::Error)
  end

  it "sends an RGB asset via /sendrgb using a recipient_map and returns the txid" do
    allow(http).to receive(:post) do |path, body, _headers|
      expect(path).to eq("/sendrgb")
      payload = JSON.parse(body)
      recipient = payload.dig("recipient_map", "rgb:abc", 0)
      expect(recipient["assignment"]).to eq("type" => "Fungible", "value" => 1000)
      expect(recipient["recipient_id"]).to eq("bcrt:utxob:xyz")
      expect(recipient["transport_endpoints"]).to eq(["rpc://rgb-proxy:3000/json-rpc"])
      ok("txid" => "deadbeef")
    end

    result = client.send_asset(
      asset_id: "rgb:abc",
      amount: 1000,
      recipient_id: "bcrt:utxob:xyz",
      transport_endpoints: ["rpc://rgb-proxy:3000/json-rpc"]
    )

    expect(result).to eq("txid" => "deadbeef")
  end

  it "produces an rgb invoice with a Fungible assignment" do
    allow(http).to receive(:post) do |path, body, _headers|
      expect(path).to eq("/rgbinvoice")
      payload = JSON.parse(body)
      expect(payload["assignment"]).to eq("type" => "Fungible", "value" => 500)
      ok("recipient_id" => "bcrt:utxob:r", "invoice" => "rgb:...")
    end

    result = client.rgb_invoice(asset_id: "rgb:abc", amount: 500)
    expect(result["recipient_id"]).to eq("bcrt:utxob:r")
  end

  it "reads asset balance via POST /assetbalance" do
    allow(http).to receive(:post) do |path, _body, _headers|
      expect(path).to eq("/assetbalance")
      ok("settled" => 777, "future" => 777, "spendable" => 777)
    end

    expect(client.asset_balance(asset_id: "rgb:abc")["settled"]).to eq(777)
  end

  it "raises a descriptive error on a non-success response" do
    allow(http).to receive(:post).and_return(bad("error" => "boom"))

    expect { client.address }.to raise_error(described_class::Error, /boom/)
  end

  it "reports availability from /nodeinfo" do
    allow(http).to receive(:get).and_return(ok("pubkey" => "02abc"))
    expect(client.available?).to be(true)
  end

  it "reports unavailable when the node is unreachable" do
    allow(http).to receive(:get).and_raise(Errno::ECONNREFUSED)
    expect(client.available?).to be(false)
  end
end
