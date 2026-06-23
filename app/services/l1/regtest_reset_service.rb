# frozen_string_literal: true

module L1
  # Ricrea bitcoind regtest da zero (catena + wallet). Usato dal reset demo con L1 on.
  class RegtestResetService
    class Error < StandardError; end

    def self.call
      new.call
    end

    def call
      return unless L1.enabled?

      script = Rails.root.join("bin/regtest")
      success = system(script.to_s, "reset", chdir: Rails.root)
      raise Error, "Reset regtest fallito (bitcoind non raggiungibile?)" unless success
    end
  end
end
