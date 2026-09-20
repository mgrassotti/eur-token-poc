# frozen_string_literal: true

module Api
  module V1
    class ReserveController < BaseController
      # Phase 2: Returns stored address (set by mobile client) or null if not yet registered.
      # Mobile clients should call PUT /reserve/update_address on first wallet creation.
      def show
        account = current_user.btc_account
        address = account.reserve_receive_address

        render json: {
          schema_version: 1,
          network: "regtest",
          receive_address: address,
          balance_sats: account.balance_sats,
          instructions: address.present? ? 
            "Send BTC on regtest to this address. An admin funds via Exchange wallet." :
            "Create an on-device wallet first (Phase 2 BDK)."
        }
      end

      # Phase 2: Mobile client registers its BDK-generated receive address.
      # Called once per wallet creation (address should be stable for the user).
      def update_address
        address = params.require(:receive_address).to_s.strip
        
        if address.blank?
          return render json: { error: "address_required" }, status: :unprocessable_entity
        end

        # Validate address format (basic check)
        unless valid_bitcoin_address?(address)
          return render json: { error: "invalid_address" }, status: :unprocessable_entity
        end

        # Check for duplicates (addresses should be unique per user)
        existing = BtcAccount.where(reserve_receive_address: address).where.not(user_id: current_user.id).first
        if existing
          return render json: { error: "address_in_use" }, status: :conflict
        end

        current_user.btc_account.update!(reserve_receive_address: address)

        render json: {
          schema_version: 1,
          receive_address: address,
          registered_at: Time.current.iso8601
        }
      end

      # Phase 2: Sync is now a no-op. Mobile clients use BDK sync directly.
      # Balance updates happen when admin funds via L1::FundReceiveAddressService.
      def sync
        account = current_user.btc_account.reload

        render json: {
          schema_version: 1,
          balance_sats: account.balance_sats,
          synced_at: Time.current.iso8601,
          note: "Phase 2: Balance synced by admin funding service. Use BDK sync on mobile for L1 state."
        }
      end

      private

      def valid_bitcoin_address?(address)
        # Basic validation: regtest addresses start with bcrt1, mainnet with bc1 or 1/3
        # For regtest: bcrt1 (bech32)
        return true if address.start_with?("bcrt1") && address.length >= 42
        # For testnet/mainnet (future): tb1, bc1, or legacy
        return true if address.match?(/\A(bc1|tb1|[13])[a-zA-HJ-NP-Z0-9]{25,62}\z/)
        
        false
      end
    end
  end
end
