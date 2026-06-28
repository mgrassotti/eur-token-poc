# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dlc::PythiaOracleClient do
  subject(:client) do
    described_class.new(base_url: "http://pythia.test:8000", asset_pair: "btc_usd", version: "v1", base: 2)
  end

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

  def not_found
    res = Net::HTTPNotFound.new("1.1", "404", "Not Found")
    res.instance_variable_set(:@body, "")
    res.instance_variable_set(:@read, true)
    res
  end

  let(:maturity) { 1_790_000_000 }
  let(:rfc3339) { Time.at(maturity).utc.iso8601 }

  let(:announcement_json) do
    {
      "announcementSignature" => "sig",
      "oraclePublicKey" => "02deadbeef",
      "oracleEvent" => {
        "oracleNonces" => %w[n0 n1 n2],
        "eventMaturityEpoch" => maturity,
        "eventDescriptor" => {
          "digitDecompositionEvent" => {
            "base" => 2, "isSigned" => false, "unit" => "usd/btc",
            "precision" => 0, "nbDigits" => 20
          }
        },
        "eventId" => "btc_usd#{maturity}"
      }
    }
  end

  it "exposes the normalized base_url and config" do
    expect(client.base_url).to eq("http://pythia.test:8000")
    expect(client.asset_pair).to eq("btc_usd")
    expect(client.version).to eq("v1")
  end

  it "raises without a base_url" do
    expect { described_class.new(base_url: "") }.to raise_error(described_class::Error)
  end

  it "is rescued by OracleClient::Error" do
    expect(described_class::Error.ancestors).to include(Dlc::OracleClient::Error)
  end

  it "reads the oracle public key" do
    allow(http).to receive(:get) do |path, _headers|
      expect(path).to eq("/v1/oracle/publickey")
      ok("publicKey" => "02deadbeef")
    end

    expect(client.oracle_pubkey).to eq("02deadbeef")
    expect(client.available?).to be(true)
  end

  it "announces by fetching the scheduled announcement for the maturity" do
    allow(http).to receive(:get) do |path, _headers|
      expect(path).to eq("/v1/asset/btc_usd/announcement/#{rfc3339}")
      ok(announcement_json)
    end

    ann = client.announce_numeric(maturity_epoch: maturity, event_id: "deal-7")

    expect(ann).to be_a(Dlc::OracleClient::Announcement)
    expect(ann.event_id).to eq("btc_usd#{maturity}")
    expect(ann.oracle_pubkey).to eq("02deadbeef")
    expect(ann.nonces).to eq(%w[n0 n1 n2])
    expect(ann.num_digits).to eq(20)
    expect(ann.unit).to eq("usd/btc")
    expect(ann.maturity_epoch).to eq(maturity)
    expect(JSON.parse(ann.hex)).to eq(announcement_json)
  end

  it "raises when no announcement is scheduled for the maturity" do
    allow(client).to receive(:sleep)
    allow(http).to receive(:get).and_return(not_found)

    expect { client.announce_numeric(maturity_epoch: maturity) }
      .to raise_error(described_class::Error, /nessun announcement/i)
  end

  it "attests via POST /force and decodes the per-digit outcome" do
    allow(http).to receive(:post) do |path, body, _headers|
      expect(path).to eq("/v1/force")
      payload = JSON.parse(body)
      expect(payload["maturation"]).to eq(rfc3339)
      expect(payload["price"]).to eq(55_000)
      ok(
        "announcement" => announcement_json,
        "attestation" => {
          "eventId" => "btc_usd#{maturity}",
          "signatures" => %w[s0 s1 s2 s3],
          "values" => %w[1 1 0 1]
        }
      )
    end

    att = client.attest_numeric(outcome: 55_000.4, maturity_epoch: maturity)

    expect(att).to be_a(Dlc::OracleClient::Attestation)
    expect(att.event_id).to eq("btc_usd#{maturity}")
    expect(att.signatures).to eq(%w[s0 s1 s2 s3])
    expect(att.digits).to eq([1, 1, 0, 1])
    expect(att.outcome).to eq(0b1101)
    expect(JSON.parse(att.hex)).to include("signatures" => %w[s0 s1 s2 s3])
  end

  it "returns nil when an attestation is not yet available" do
    allow(http).to receive(:get).and_return(not_found)

    expect(client.attestation(maturity_epoch: maturity)).to be_nil
  end

  it "reports unavailable when the oracle is unreachable" do
    allow(http).to receive(:get).and_raise(Errno::ECONNREFUSED)

    expect(client.available?).to be(false)
  end
end
