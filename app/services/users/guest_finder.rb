# frozen_string_literal: true

module Users
  # Finds or creates an ephemeral user keyed by on-device funding address.
  # Used for anonymous mobile top-ups (no email/password login).
  class GuestFinder
    def self.find_or_create_by_address!(address:, name: "Anonymous")
      new(address: address, name: name).call
    end

    def initialize(address:, name: "Anonymous")
      @address = address.to_s.strip
      @name = name.presence || "Anonymous"
    end

    def call
      raise ArgumentError, "funding_address required" if @address.blank?

      email = guest_email
      user = User.find_or_initialize_by(email: email)
      if user.new_record?
        user.name = @name
        user.password = SecureRandom.hex(32)
        user.save!
      end

      account = user.btc_account
      if account.reserve_receive_address != @address
        account.update!(reserve_receive_address: @address)
      end

      user
    end

    private

    def guest_email
      digest = Digest::SHA256.hexdigest(@address.downcase)[0, 16]
      "anon+#{digest}@guest.local"
    end
  end
end
