# frozen_string_literal: true

module Api
  # Signed bearer tokens for the Phase 1 relay API (no keys — identity only).
  class AuthToken
    PURPOSE = :relay_api_v1

    class << self
      def generate(user, expires_in: 24.hours)
        payload = { "user_id" => user.id, "exp" => expires_in.from_now.to_i }
        verifier.generate(payload)
      end

      def verify(token)
        payload = verifier.verify(token)
        return nil if payload["exp"].to_i < Time.now.to_i

        User.find_by(id: payload["user_id"])
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        nil
      end

      private

      def verifier
        Rails.application.message_verifier(PURPOSE)
      end
    end
  end
end
