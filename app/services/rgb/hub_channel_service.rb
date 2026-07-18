# frozen_string_literal: true

module Rgb
  # Ensures Alice↔hub and recipient↔hub RGB-LN capacity for an amount.
  #
  # Topology (RLN multi_hop pattern):
  #   Alice --RGB channel--> Hub --RGB channel--> Claude
  #
  # Hub needs off-channel EURT to lock into the Claude edge (inbound for Claude).
  # PoC seeds that by an L1 RGB transfer Alice→hub when hub settled is short —
  # so first send of X may require ~2X of Alice's off-channel balance (X to hub
  # liquidity + X into Alice's channel). Subsequent sends reuse open channels.
  class HubChannelService
    class Error < StandardError; end

    CHANNEL_CAPACITY_SAT = 100_000
    # Matches RLN multi_hop: leave peer with BTC so HTLCs can settle.
    PUSH_MSAT = 3_500_000
    CHANNEL_CONFIRM_BLOCKS = 6
    OPEN_TIMEOUT_SEC = 120
    READY_TIMEOUT_SEC = 90

    def self.ensure_capacity!(from_user:, to_user:, asset_id:, amount_cents:, budget: nil)
      new(from_user:, to_user:, asset_id:, amount_cents:, budget:).ensure_capacity!
    end

    def initialize(from_user:, to_user:, asset_id:, amount_cents:, budget: nil)
      @from_user = from_user
      @to_user = to_user
      @asset_id = asset_id
      @amount_cents = amount_cents.to_i
      @budget = budget
      @hub_seeded = 0
    end

    def ensure_capacity!
      raise Error, I18n.t("services.rgb.hub_channel.invalid_amount") unless amount_cents.positive?
      raise Error, I18n.t("services.rgb.hub_channel.missing_asset_id") if asset_id.blank?

      sender = WalletSetupService.ensure_for!(from_user)
      recipient = WalletSetupService.ensure_for!(to_user)
      hub = HubSetupService.call

      ensure_recipient_inbound!(sender:, recipient:, hub:)
      ensure_sender_outbound!(sender:, hub:)

      {
        sender_outbound: offchain_outbound(sender),
        recipient_inbound: offchain_inbound(recipient),
        hub_seeded: @hub_seeded
      }
    end

    private

    attr_reader :from_user, :to_user, :asset_id, :amount_cents, :budget

    def ensure_recipient_inbound!(sender:, recipient:, hub:)
      shortfall = amount_cents - offchain_inbound(recipient)
      return if shortfall <= 0

      # Size fresh liquidity for ≥2 payments so a follow-up send needs no L1 seed.
      open_amount = shortfall * 2

      hub_settled = settled(hub)
      seed_hub_from_sender!(sender:, hub:, amount: open_amount - hub_settled) if hub_settled < open_amount

      hub_settled = settled(hub)
      raise Error, I18n.t("services.rgb.hub_channel.hub_insufficient_liquidity",
        need: open_amount, have: hub_settled) if hub_settled < open_amount

      open_rgb_channel!(
        opener: hub,
        peer: recipient,
        peer_user: to_user,
        asset_amount: open_amount
      )
    end

    def ensure_sender_outbound!(sender:, hub:)
      shortfall = amount_cents - offchain_outbound(sender)
      return if shortfall <= 0

      open_amount = shortfall * 2
      sender_settled = settled(sender)
      raise Error, I18n.t("services.rgb.hub_channel.sender_insufficient_for_channel",
        need: open_amount, have: sender_settled) if sender_settled < open_amount

      open_rgb_channel!(
        opener: sender,
        peer: hub,
        peer_user: nil,
        peer_addr: Config.rln_hub_peer_addr,
        peer_pubkey: hub.node_pubkey,
        asset_amount: open_amount
      )
    end

    # L1 RGB Alice→hub so the hub can lock EURT into the recipient edge.
    def seed_hub_from_sender!(sender:, hub:, amount:)
      available = settled(sender)
      raise Error, I18n.t("services.rgb.hub_channel.sender_insufficient_for_hub_seed",
        need: amount, have: available) if available < amount

      invoice = hub.rgb_invoice(amount: amount)
      recipient_id = invoice.fetch("recipient_id")
      sender.send_asset(
        asset_id: asset_id,
        amount: amount,
        recipient_id: recipient_id,
        transport_endpoints: [Config.rln_unlock_params[:proxy_endpoint]]
      )
      NodeConfirm.settle_clients!(sender, hub)
      @hub_seeded += amount

      if budget
        ProjectionService.apply_hub_seed!(
          budget: budget,
          from_user: from_user,
          amount_cents: amount
        )
      end
    end

    def open_rgb_channel!(opener:, peer:, asset_amount:, peer_user: nil,
                          peer_addr: nil, peer_pubkey: nil)
      pubkey = peer_pubkey || peer.node_pubkey
      addr = peer_addr || Config.rln_peer_addr_for_url(peer_user ? Nodes.for_user(peer_user).base_url : peer.base_url)
      peer_string = "#{pubkey}@#{addr}"

      # Reuse an in-flight or already-ready channel for this peer/asset when possible.
      existing = opener.channels.find do |c|
        c["peer_pubkey"] == pubkey &&
          c["asset_id"] == asset_id &&
          c["asset_local_amount"].to_i >= asset_amount &&
          (c["ready"] || c["funding_txid"].present?)
      end
      if existing
        return existing if existing["ready"]

        NodeConfirm.mine!(CHANNEL_CONFIRM_BLOCKS) if existing["funding_txid"].present?
        return wait_channel_ready!(opener, peer_pubkey: pubkey, asset_amount: existing["asset_local_amount"].to_i,
                                   channel_id: existing["channel_id"])
      end

      safe_connect!(opener, peer_string)
      safe_connect!(peer, opener_peer_string(opener))

      opener.open_channel(
        peer_pubkey_and_opt_addr: peer_string,
        capacity_sat: CHANNEL_CAPACITY_SAT,
        push_msat: PUSH_MSAT,
        asset_id: asset_id,
        asset_amount: asset_amount
      )

      wait_channel_ready!(opener, peer_pubkey: pubkey, asset_amount: asset_amount)
    end

    def opener_peer_string(opener)
      pubkey = opener.node_pubkey
      addr = if opener.base_url == Config.rln_hub_url.chomp("/") ||
                opener.base_url == Config.rln_issuer_url.chomp("/")
               Config.rln_hub_peer_addr
             else
               Config.rln_peer_addr_for_url(opener.base_url)
             end
      "#{pubkey}@#{addr}"
    end

    def safe_connect!(client, peer_string)
      client.connect_peer(peer_pubkey_and_addr: peer_string)
    rescue LightningClient::Error => e
      raise unless e.message.match?(/already|connected|in progress/i)
    end

    def wait_channel_ready!(opener, peer_pubkey:, asset_amount:, channel_id: nil)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + OPEN_TIMEOUT_SEC

      until channel_id
        raise Error, I18n.t("services.rgb.hub_channel.open_timeout") if timed_out?(deadline)

        sleep 1
        pending = opener.channels.find do |c|
          !c["ready"] &&
            c["peer_pubkey"] == peer_pubkey &&
            c["asset_id"] == asset_id &&
            c["asset_local_amount"].to_i == asset_amount &&
            c["funding_txid"].present?
        end
        next unless pending

        NodeConfirm.mine!(CHANNEL_CONFIRM_BLOCKS)
        channel_id = pending["channel_id"]
      end

      ready_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + READY_TIMEOUT_SEC
      mined = 0
      loop do
        channel = opener.channels.find { |c| c["channel_id"] == channel_id }
        return channel if channel&.dig("ready")
        raise Error, I18n.t("services.rgb.hub_channel.ready_timeout") if timed_out?(ready_deadline)

        # Electrs/RLN can lag behind bitcoind; nudge with extra confirms.
        if mined < 6
          NodeConfirm.mine!(1)
          mined += 1
        end
        sleep 2
      end
    end

    def timed_out?(deadline)
      Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end

    def asset_balance(client)
      client.asset_balance(asset_id: asset_id)
    rescue LightningClient::Error => e
      # Node has never seen this contract (e.g. hub before first seed).
      raise unless e.message.match?(/Unknown RGB contract|UnknownContractId|AssetNotFound/i)

      { "settled" => 0, "offchain_outbound" => 0, "offchain_inbound" => 0, "spendable" => 0 }
    end

    def settled(client)
      asset_balance(client)["settled"].to_i
    end

    def offchain_outbound(client)
      asset_balance(client)["offchain_outbound"].to_i
    end

    def offchain_inbound(client)
      asset_balance(client)["offchain_inbound"].to_i
    end
  end
end
