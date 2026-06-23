# frozen_string_literal: true

module L1
  module DealSigning
    module_function

    def investor_wif_for(budget)
      wif = budget.recovery_package&.dig("party_signing", "investor", "wif")
      return wif if wif.present?

      legacy_party_wif(
        budget: budget,
        user: budget.investor,
        expected_pubkey: budget.investor_pubkey,
        role: "investitore"
      )
    end

    def peg_party_wif_for(budget)
      wif = budget.recovery_package&.dig("party_signing", "peg_party", "wif")
      return wif if wif.present?

      legacy_party_wif(
        budget: budget,
        user: budget.borrower,
        expected_pubkey: budget.peg_party_pubkey,
        role: "richiedente"
      )
    end

    def legacy_party_wif(budget:, user:, expected_pubkey:, role:)
      wallet = UserWallet.for(user)
      wif = wallet.escrow_identity_wif
      pubkey = wallet.identity_pubkey
      return wif if pubkey == expected_pubkey

      raise SettlementSpendService::Error,
            "Chiave #{role} non allineata all'escrow del deal ##{budget.id} " \
            "(pubkey escrow #{expected_pubkey&.first(16)}…, conto #{pubkey&.first(16)}…). " \
            "Esegui reset demo e riattiva il deal."
    end
  end
end
