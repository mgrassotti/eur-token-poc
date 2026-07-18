# frozen_string_literal: true

module Rgb
  # Ensures the MAT liquidity hub RLN is unlocked, funded, and has colorable UTXOs
  # so it can accept Alice→hub channels and open hub→recipient RGB channels.
  class HubSetupService
    class Error < StandardError; end

    FUND_SATS = WalletSetupService::FUND_SATS
    MIN_VANILLA_SATS = WalletSetupService::MIN_VANILLA_SATS
    COLORABLE_UTXOS = WalletSetupService::COLORABLE_UTXOS
    COLORABLE_UTXO_SIZE = WalletSetupService::COLORABLE_UTXO_SIZE
    FEE_RATE = WalletSetupService::FEE_RATE

    def self.call
      new.call
    end

    def call
      hub = Nodes.hub
      begin
        hub.init(password: Config.rln_password)
      rescue LightningClient::Error
        nil # already initialized
      end

      begin
        hub.unlock(password: Config.rln_password, **Config.rln_unlock_params)
      rescue LightningClient::Error => e
        # Already unlocked is fine; indexer/auth failures must surface.
        raise Error, e.message unless e.message.match?(/already been unlocked|already unlocked/i)
      end

      fund_btc!(hub)
      begin
        hub.create_utxos(up_to: true, num: COLORABLE_UTXOS, size: COLORABLE_UTXO_SIZE, fee_rate: FEE_RATE)
      rescue LightningClient::Error => e
        Rails.logger.warn("RLN hub createutxos saltato: #{e.message}")
      end
      NodeConfirm.mine!
      begin
        hub.refresh_transfers
      rescue LightningClient::Error
        nil
      end
      hub
    end

    private

    def fund_btc!(hub)
      return unless regtest?
      return if hub.btc_balance.dig("vanilla", "spendable").to_i >= MIN_VANILLA_SATS

      address = hub.address.fetch("address")
      harness = L1::RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET)
      harness.ensure_chain_ready!
      harness.fund_address!(address, sats: FUND_SATS)
    rescue LightningClient::Error => e
      Rails.logger.warn("RLN hub funding saltato: #{e.message}")
    end

    def regtest?
      L1::Bitcoind::Client.new.available?
    rescue StandardError
      false
    end
  end
end
