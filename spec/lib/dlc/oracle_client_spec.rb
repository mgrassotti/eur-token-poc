# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dlc::OracleClient do
  subject(:client) { described_class.new(base_url: "http://oracle.test:8080") }

  # Minimal Net::HTTP fake: records the last request and returns a canned body,
  # mirroring spec/lib/rgb/lightning_client_spec.rb.
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

  it "exposes the normalized base_url" do
    expect(client.base_url).to eq("http://oracle.test:8080")
  end

  it "raises without a base_url" do
    expect { described_class.new(base_url: "") }.to raise_error(described_class::Error)
  end

  it "reads the oracle public key from /pubkey" do
    allow(http).to receive(:get) do |path, _headers|
      expect(path).to eq("/pubkey")
      ok("pubkey" => "02deadbeef")
    end

    expect(client.oracle_pubkey).to eq("02deadbeef")
    expect(client.available?).to be(true)
  end

  it "announces a numeric event with per-digit nonces" do
    allow(http).to receive(:post) do |path, body, _headers|
      expect(path).to eq("/create-numeric-event")
      payload = JSON.parse(body)
      expect(payload["event_id"]).to eq("deal-7")
      expect(payload["num_digits"]).to eq(20)
      expect(payload["unit"]).to eq("EUR/BTC")
      expect(payload["event_maturity_epoch"]).to eq(1_790_000_000)
      ok(
        "event_id" => "deal-7",
        "announcement" => "abc123",
        "oracle_public_key" => "02deadbeef",
        "oracle_nonces" => %w[n0 n1 n2],
        "num_digits" => 20,
        "unit" => "EUR/BTC",
        "event_maturity_epoch" => 1_790_000_000
      )
    end

    ann = client.announce_numeric(
      event_id: "deal-7",
      maturity_epoch: 1_790_000_000,
      num_digits: 20
    )

    expect(ann).to be_a(described_class::Announcement)
    expect(ann.event_id).to eq("deal-7")
    expect(ann.hex).to eq("abc123")
    expect(ann.oracle_pubkey).to eq("02deadbeef")
    expect(ann.nonces).to eq(%w[n0 n1 n2])
    expect(ann.num_digits).to eq(20)
    expect(ann.maturity_epoch).to eq(1_790_000_000)
  end

  it "attests a numeric outcome with per-digit signatures" do
    allow(http).to receive(:post) do |path, body, _headers|
      expect(path).to eq("/sign-numeric-event")
      payload = JSON.parse(body)
      expect(payload["event_id"]).to eq("deal-7")
      expect(payload["outcome"]).to eq(55_000)
      ok(
        "event_id" => "deal-7",
        "attestation" => "deadbeef",
        "oracle_public_key" => "02deadbeef",
        "outcome" => 55_000,
        "outcome_digits" => [1, 1, 0, 1],
        "signatures" => %w[s0 s1 s2 s3]
      )
    end

    att = client.attest_numeric(event_id: "deal-7", outcome: 55_000)

    expect(att).to be_a(described_class::Attestation)
    expect(att.outcome).to eq(55_000)
    expect(att.digits).to eq([1, 1, 0, 1])
    expect(att.signatures).to eq(%w[s0 s1 s2 s3])
    expect(att.hex).to eq("deadbeef")
  end

  it "fetches an announcement via GET /event/:id" do
    allow(http).to receive(:get) do |path, _headers|
      expect(path).to eq("/event/deal-7")
      ok("event_id" => "deal-7", "announcement" => "abc123", "num_digits" => 20)
    end

    expect(client.announcement(event_id: "deal-7").hex).to eq("abc123")
  end

  it "returns nil when an event has no attestation yet" do
    allow(http).to receive(:get).and_return(ok("event_id" => "deal-7", "announcement" => "abc123"))

    expect(client.attestation(event_id: "deal-7")).to be_nil
  end

  it "returns the attestation once the event is signed" do
    allow(http).to receive(:get).and_return(
      ok("event_id" => "deal-7", "attestation" => "deadbeef", "outcome" => 55_000)
    )

    expect(client.attestation(event_id: "deal-7").outcome).to eq(55_000)
  end

  it "raises a descriptive error on a non-success response" do
    allow(http).to receive(:post).and_return(bad("error" => "unknown event"))

    expect { client.attest_numeric(event_id: "x", outcome: 1) }
      .to raise_error(described_class::Error, /unknown event/)
  end

  it "reports unavailable when the oracle is unreachable" do
    allow(http).to receive(:get).and_raise(Errno::ECONNREFUSED)

    expect(client.available?).to be(false)
  end
end
