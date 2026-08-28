# frozen_string_literal: true

class BankAccount < ApplicationRecord
  DEFAULT_IBAN = "IT60X0300203280123456789012"
  DEFAULT_NAME = "MAT Banca"

  has_many :bank_transfers, dependent: :destroy

  validates :iban, :name, presence: true
  validates :iban, uniqueness: true

  def self.default
    find_by(default: true) || create_default!
  end

  def self.create_default!
    create!(
      name: DEFAULT_NAME,
      iban: DEFAULT_IBAN,
      default: true,
      balance_eur_cents: 0,
      btc_receive_address: "bcrt1qmatbankpayout00000000000000000000000000"
    )
  end

  def credit!(amount_cents)
    increment!(:balance_eur_cents, amount_cents)
  end

  def debit!(amount_cents)
    raise ArgumentError, "insufficient bank balance" if balance_eur_cents < amount_cents

    decrement!(:balance_eur_cents, amount_cents)
  end
end
