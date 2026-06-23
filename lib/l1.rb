# frozen_string_literal: true

module L1
  # Shared regtest wallet for coinbase / funding (reused across budgets).
  SHARED_REGTEST_WALLET = "l1_regtest"

  class << self
    def enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("L1_ENABLED", false))
    end
  end
end
