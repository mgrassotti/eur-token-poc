# frozen_string_literal: true

module Rgb
  # Resolves the RGB Lightning Node (RLN) instance backing a given user, plus the
  # shared issuer/treasury node. Replaces the single Rgb::SidecarClient.instance:
  # in the RLN model each user owns a node, addressed by BtcAccount#rln_node_url.
  module Nodes
    class Error < StandardError; end

    module_function

    def for_user(user)
      account = user.btc_account || user.create_btc_account!
      url = account.rln_node_url.presence
      raise Error, "RLN node non configurato per utente #{user.id}" if url.blank?

      LightningClient.new(base_url: url, token: account.rln_token.presence || Config.rln_token)
    end

    def for_user?(user)
      user.btc_account&.rln_node_url.present?
    end

    def issuer
      LightningClient.new(base_url: Config.rln_issuer_url, token: Config.rln_token)
    end

    # True when the user's node is reachable (used to choose RLN vs DB fallback).
    def available_for?(user)
      for_user?(user) && for_user(user).available?
    rescue Error, LightningClient::Error
      false
    end
  end
end
