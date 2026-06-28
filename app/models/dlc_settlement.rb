# frozen_string_literal: true

# The maturity outcome of a DLC contract: the broadcast CET (or refund) with
# the oracle attestation that unlocked it and the resulting sats split.
class DlcSettlement < ApplicationRecord
  belongs_to :budget
  belongs_to :dlc_contract

  enum :status, { pending: 0, executed: 1, refunded: 2, failed: 3 }
end
