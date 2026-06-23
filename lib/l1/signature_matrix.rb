# frozen_string_literal: true

module L1
  # Which 2-of-3 pairs can sign — MULTISIG-SPEC §4 (documented + testable).
  module SignatureMatrix
    PAIRS = [
      %i[peg_party investor],
      %i[peg_party bot],
      %i[investor bot]
    ].freeze

    def self.valid_pair?(first, second)
      pair = [first.to_sym, second.to_sym].sort
      PAIRS.any? { |candidate| candidate.sort == pair }
    end

    def self.bot_only?(signers)
      Array(signers).map { |s| role_name(s) } == [:bot]
    end

    def self.role_name(signer)
      return signer.to_sym unless signer.respond_to?(:label)

      signer.label.to_sym
    end
  end
end
