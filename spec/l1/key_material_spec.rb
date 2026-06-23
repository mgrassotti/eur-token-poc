# frozen_string_literal: true

require "rails_helper"

RSpec.describe L1::KeyMaterial do
  it "generates compressed secp256k1 keys" do
    key = described_class.generate

    expect(key.private_key_hex).to match(/\A[0-9a-f]{64}\z/)
    expect(key.public_key_hex).to match(/\A(02|03)[0-9a-f]{64}\z/)
  end

  it "encodes regtest WIF" do
    key = described_class.generate

    expect(key.wif(testnet: true)).to match(/\A[9cHJKLMNPQRSTUVwxyz][1-9A-HJ-NP-Za-km-z]+\z/)
  end
end
