# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dlc::Numeric do
  describe ".digits" do
    it "decomposes into a fixed-width big-endian base-2 array" do
      expect(described_class.digits(5, num_digits: 4)).to eq([0, 1, 0, 1])
    end

    it "zero-pads small values to num_digits" do
      expect(described_class.digits(1, num_digits: 8)).to eq([0, 0, 0, 0, 0, 0, 0, 1])
    end

    it "supports the maximum representable value" do
      expect(described_class.digits(255, num_digits: 8)).to eq([1] * 8)
    end

    it "supports an arbitrary base" do
      expect(described_class.digits(123, num_digits: 3, base: 10)).to eq([1, 2, 3])
    end

    it "rejects negative outcomes" do
      expect { described_class.digits(-1, num_digits: 4) }
        .to raise_error(ArgumentError, /negative/)
    end

    it "rejects values that overflow the digit width" do
      expect { described_class.digits(16, num_digits: 4) }
        .to raise_error(ArgumentError, /exceeds/)
    end
  end

  describe ".from_digits" do
    it "is the inverse of .digits" do
      digits = described_class.digits(54_321, num_digits: 20)
      expect(described_class.from_digits(digits)).to eq(54_321)
    end

    it "folds an explicit base-10 array" do
      expect(described_class.from_digits([1, 2, 3], base: 10)).to eq(123)
    end
  end

  describe ".max_value" do
    it "returns base**num_digits - 1" do
      expect(described_class.max_value(num_digits: 20)).to eq(1_048_575)
    end
  end

  describe ".required_digits" do
    it "returns the minimum width to cover max_value" do
      expect(described_class.required_digits(255)).to eq(8)
      expect(described_class.required_digits(256)).to eq(9)
    end

    it "never returns fewer than one digit" do
      expect(described_class.required_digits(0)).to eq(1)
    end
  end
end
