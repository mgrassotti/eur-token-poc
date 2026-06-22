# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChainState do
  describe ".estimate_block_height" do
    it "estimates height from elapsed time since genesis (10 min/block)" do
      at = ChainState::GENESIS_TIME_UTC + (100 * ChainState::SECONDS_PER_BLOCK)

      expect(described_class.estimate_block_height(at: at)).to eq(100)
    end

    it "returns 0 before genesis" do
      expect(described_class.estimate_block_height(at: ChainState::GENESIS_TIME_UTC - 1)).to eq(0)
    end
  end
end
