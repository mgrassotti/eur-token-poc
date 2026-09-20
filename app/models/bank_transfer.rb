# frozen_string_literal: true

class BankTransfer < ApplicationRecord
  belongs_to :bank_account
  belongs_to :funding_request, optional: true
  belongs_to :budget, optional: true

  enum :direction, { inbound: 0, outbound: 1 }
  enum :status, { pending: 0, completed: 1, failed: 2 }

  validates :amount_eur_cents, numericality: { only_integer: true, greater_than: 0 }
end
