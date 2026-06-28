# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rgb::Nodes do
  let(:user) { create(:user) }

  it "raises when the user has no node URL configured" do
    user.btc_account.update!(rln_node_url: nil)

    expect { described_class.for_user(user) }.to raise_error(described_class::Error)
  end

  it "builds a per-user client from the account node URL" do
    user.btc_account.update!(rln_node_url: "http://127.0.0.1:3001")

    client = described_class.for_user(user)

    expect(client).to be_a(Rgb::LightningClient)
    expect(client.base_url).to eq("http://127.0.0.1:3001")
  end

  it "builds the issuer client from config" do
    expect(described_class.issuer.base_url).to eq(Rgb::Config.rln_issuer_url.chomp("/"))
  end

  it "reports unavailable when no node URL is set" do
    user.btc_account.update!(rln_node_url: nil)

    expect(described_class.available_for?(user)).to be(false)
  end
end
