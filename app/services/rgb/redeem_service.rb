# frozen_string_literal: true

module Rgb
  # Redemption (ritiro) RGB20 EURT a settlement: drena il saldo settled del holder
  # verso il nodo issuer/treasury. RGB non espone un burn nativo, quindi la
  # redemption all'issuer ritira di fatto i token dalla circolazione degli holder
  # in cambio del payout BTC dell'escrow. Operazione solo on-chain via RLN:
  # nessuna scrittura DB qui — la proiezione la aggiorna ProjectionService.apply_redeem!.
  class RedeemService
    class Error < StandardError; end

    Result = Data.define(:asset_id, :amount_cents, :txid, :recipient_id, :status)

    def self.call(budget:, holder:)
      new(budget:, holder:).call
    end

    def initialize(budget:, holder:)
      @budget = budget
      @holder = holder
    end

    def call
      return skipped unless redeemable?

      amount_cents = BalanceService.settled(user: holder, budget: budget)
      return empty(amount_cents) if amount_cents <= 0

      issuer = ensure_issuer_node!
      holder_node = WalletSetupService.ensure_for!(holder)

      invoice = issuer.rgb_invoice(amount: amount_cents)
      recipient_id = invoice.fetch("recipient_id")

      transfer = holder_node.send_asset(
        asset_id: asset_id,
        amount: amount_cents,
        recipient_id: recipient_id,
        transport_endpoints: [Config.rln_unlock_params[:proxy_endpoint]]
      )

      NodeConfirm.settle_clients!(holder_node, issuer)

      Result.new(
        asset_id: asset_id,
        amount_cents: amount_cents,
        txid: transfer.fetch("txid"),
        recipient_id: recipient_id,
        status: :redeemed
      )
    end

    private

    attr_reader :budget, :holder

    def redeemable?
      asset_id.present? && Nodes.available_for?(holder)
    end

    def asset_id
      budget.rgb_asset_id
    end

    # Provisions the issuer/treasury node so it can mint a blind invoice
    # (needs a colorable UTXO): init, unlock, fund (regtest) and create UTXOs.
    def ensure_issuer_node!
      issuer = Nodes.issuer
      safe(issuer) { issuer.init(password: Config.rln_password) }
      safe(issuer) { issuer.unlock(password: Config.rln_password, **Config.rln_unlock_params) }
      fund_issuer_btc!(issuer)
      safe(issuer) { issuer.create_utxos(up_to: true, num: 5, size: 32_500, fee_rate: 5) }
      NodeConfirm.mine!
      safe(issuer) { issuer.refresh_transfers }
      issuer
    end

    def fund_issuer_btc!(issuer)
      return unless NodeConfirm.regtest?
      return if issuer.btc_balance.dig("vanilla", "spendable").to_i >= WalletSetupService::MIN_VANILLA_SATS

      address = issuer.address.fetch("address")
      harness = L1::RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET)
      harness.ensure_chain_ready!
      harness.fund_address!(address, sats: WalletSetupService::FUND_SATS)
    rescue LightningClient::Error => e
      Rails.logger.warn("RLN issuer funding saltato: #{e.message}")
    end

    def safe(_client)
      yield
    rescue LightningClient::Error
      nil
    end

    def skipped
      Result.new(asset_id: asset_id, amount_cents: 0, txid: nil, recipient_id: nil, status: :skipped)
    end

    def empty(amount_cents)
      Result.new(asset_id: asset_id, amount_cents: amount_cents, txid: nil, recipient_id: nil, status: :empty)
    end
  end
end
