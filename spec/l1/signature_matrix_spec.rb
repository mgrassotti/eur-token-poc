# frozen_string_literal: true

require "rails_helper"

RSpec.describe L1::SignatureMatrix do
  it "accepts peg_party + investor" do
    expect(described_class.valid_pair?(:peg_party, :investor)).to be(true)
  end

  it "accepts peg_party + bot" do
    expect(described_class.valid_pair?(:bot, :peg_party)).to be(true)
  end

  it "rejects single bot signer" do
    bot = Struct.new(:label).new("bot")
    expect(described_class.bot_only?([bot])).to be(true)
    expect(described_class.valid_pair?(:bot, :bot)).to be(false)
  end
end
