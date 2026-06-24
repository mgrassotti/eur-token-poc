# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::ReserveRequirement do
  let(:alice) { create(:user) }

  before do
    MarketRate.current.update!(btc_eur_per_btc: 55_000)
    alice.btc_account.update!(balance_sats: 918_181)
  end

  describe ".max_eur_cents_for" do
    it "returns the floor EUR cents coverable by available sats" do
      expect(described_class.max_eur_cents_for(alice)).to eq(50_499) # €504.99
    end

    it "uses on-chain spendable sats via UserWallet" do
      allow(L1::UserWallet).to receive(:for).with(alice).and_return(
        instance_double(L1::UserWallet, spendable_sats: 918_181)
      )

      expect(described_class.max_eur_cents_for(alice)).to eq(50_499)
    end
  end
end
