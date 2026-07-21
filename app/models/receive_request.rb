# frozen_string_literal: true

class ReceiveRequest < ApplicationRecord
  TTL = 15.minutes

  belongs_to :user
  belongs_to :paid_by_user, class_name: "User", optional: true

  validates :public_id, presence: true, uniqueness: true
  validates :recipient_id, presence: true
  validates :expires_at, presence: true

  before_validation :assign_public_id, on: :create

  scope :unpaid, -> { where(paid_at: nil) }

  def expired?
    expires_at <= Time.current
  end

  def paid?
    paid_at.present?
  end

  def payable?
    !paid? && !expired?
  end

  def qr_payload
    params = { "u" => user_id.to_s, "rid" => public_id }
    params["a"] = amount_eur_cents.to_s if amount_eur_cents.present?
    "mat:pay/1?#{URI.encode_www_form(params)}"
  end

  def mark_paid!(by_user:)
    update!(paid_at: Time.current, paid_by_user: by_user)
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end
