# frozen_string_literal: true

require "rails_helper"

RSpec.describe BtcConversion do
  describe ".sats_to_eur" do
    it "converts sats to eur at given rate" do
      expect(described_class.sats_to_eur(10_000_000, 60_000)).to eq(6000.0)
    end
  end
end
