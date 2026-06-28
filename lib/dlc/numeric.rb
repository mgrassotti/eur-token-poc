# frozen_string_literal: true

module Dlc
  # Numeric outcome <-> per-digit decomposition for DLC numeric events.
  #
  # DLC numeric events ("DigitDecomposition") attest to a value one digit at a
  # time: the oracle publishes one nonce per digit and, at maturity, one
  # signature per digit. CET payout curves are then expressed over digit
  # prefixes. This module converts between an integer outcome and its
  # fixed-width, big-endian digit array (base 2 by default), matching Kormir's
  # `create_numeric_event` / `sign_numeric_event` semantics.
  module Numeric
    module_function

    DEFAULT_BASE = 2

    # Big-endian digit array of exactly `num_digits` digits for an unsigned
    # integer outcome. Index 0 is the most-significant digit.
    def digits(value, num_digits:, base: DEFAULT_BASE)
      value = Integer(value)
      raise ArgumentError, "base must be >= 2 (got #{base})" if base < 2
      raise ArgumentError, "num_digits must be positive (got #{num_digits})" if num_digits < 1
      raise ArgumentError, "negative outcome unsupported (unsigned event): #{value}" if value.negative?

      if value > max_value(num_digits: num_digits, base: base)
        raise ArgumentError, "outcome #{value} exceeds #{num_digits}-digit base-#{base} capacity"
      end

      out = Array.new(num_digits, 0)
      remaining = value
      (num_digits - 1).downto(0) do |i|
        out[i] = remaining % base
        remaining /= base
      end
      out
    end

    # Inverse of #digits: fold a big-endian digit array back into an integer.
    def from_digits(digits, base: DEFAULT_BASE)
      digits.reduce(0) { |acc, d| (acc * base) + Integer(d) }
    end

    # Largest outcome representable with `num_digits` digits in the given base.
    def max_value(num_digits:, base: DEFAULT_BASE)
      (base**num_digits) - 1
    end

    # Minimum number of digits needed to represent `max_value` in `base`.
    def required_digits(max_value, base: DEFAULT_BASE)
      max_value = Integer(max_value)
      raise ArgumentError, "max_value must be non-negative" if max_value.negative?

      n = 0
      cap = 1
      while cap <= max_value
        cap *= base
        n += 1
      end
      [n, 1].max
    end
  end
end
