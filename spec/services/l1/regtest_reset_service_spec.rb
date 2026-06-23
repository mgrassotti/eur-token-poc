# frozen_string_literal: true

require "rails_helper"

RSpec.describe L1::RegtestResetService do
  describe ".call" do
    it "does nothing when L1 is disabled" do
      allow(L1).to receive(:enabled?).and_return(false)

      expect { described_class.call }.not_to raise_error
    end

    it "runs bin/regtest reset when L1 is enabled" do
      allow(L1).to receive(:enabled?).and_return(true)
      script = Rails.root.join("bin/regtest")
      allow_any_instance_of(described_class).to receive(:system)
        .with(script.to_s, "reset", chdir: Rails.root)
        .and_return(true)

      described_class.call
    end

    it "raises when regtest reset fails" do
      allow(L1).to receive(:enabled?).and_return(true)
      allow_any_instance_of(described_class).to receive(:system).and_return(false)

      expect { described_class.call }.to raise_error(L1::RegtestResetService::Error, /Reset regtest fallito/)
    end
  end
end
