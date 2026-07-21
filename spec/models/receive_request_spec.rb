# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiveRequest do
  let(:user) { create(:user) }

  it "builds a versioned mat:pay QR payload" do
    req = described_class.create!(
      user: user,
      amount_eur_cents: 5_000,
      recipient_id: "rcp",
      expires_at: 15.minutes.from_now
    )

    expect(req.qr_payload).to eq("mat:pay/1?u=#{user.id}&rid=#{req.public_id}&a=5000")
  end

  it "is payable only before expiry and payment" do
    req = described_class.create!(
      user: user,
      recipient_id: "rcp",
      expires_at: 15.minutes.from_now
    )
    expect(req).to be_payable

    req.mark_paid!(by_user: create(:user))
    expect(req).not_to be_payable
  end
end
