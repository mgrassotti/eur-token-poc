# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password

  has_one :btc_account, dependent: :destroy
  has_many :token_accounts, dependent: :destroy
  has_many :borrowed_budgets, class_name: "Budget", foreign_key: :borrower_id, inverse_of: :borrower, dependent: :destroy
  has_many :invested_budgets, class_name: "Budget", foreign_key: :investor_id, inverse_of: :investor, dependent: :nullify
  has_many :sent_token_transfers, class_name: "TokenTransfer", foreign_key: :from_user_id, inverse_of: :from_user, dependent: :destroy
  has_many :received_token_transfers, class_name: "TokenTransfer", foreign_key: :to_user_id, inverse_of: :to_user, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :admins, -> { where(admin: true) }

  normalizes :email, with: ->(email) { email.strip.downcase }

  after_create :create_btc_account!

  def balance_sats
    btc_account.balance_sats
  end

  def balance_btc
    BtcConversion.sats_to_btc(balance_sats)
  end
end
