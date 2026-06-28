# frozen_string_literal: true

# Helpers for integration specs that exercise the real RGB stack on RGB
# Lightning Nodes (tags :rgb_lib / :demo_flow). Requires ./bin/regtest up.
module RgbLibHelpers
  # Host API ports for the per-user RLN nodes (see docker-compose.regtest.yml).
  NODE_URLS = [
    "http://127.0.0.1:3001",
    "http://127.0.0.1:3002",
    "http://127.0.0.1:3003",
    "http://127.0.0.1:3004"
  ].freeze

  module_function

  # Assigns RLN nodes to the given users (in order) so Rgb::Nodes can resolve them.
  def assign_rln_nodes!(*users)
    users.each_with_index do |user, index|
      url = NODE_URLS.fetch(index)
      account = user.btc_account || user.create_btc_account!
      account.update!(rln_node_url: url)
    end
  end

  def rln_settled(user, asset_id)
    Rgb::Nodes.for_user(user).asset_balance(asset_id: asset_id)["settled"].to_i
  end

  def rln_available?
    Rgb::LightningClient.new(base_url: NODE_URLS.first).reachable? &&
      L1::Bitcoind::Client.new.available?
  rescue StandardError
    false
  end
end

RSpec.configure do |config|
  config.include RgbLibHelpers, rgb_lib: true
  config.include RgbLibHelpers, demo_flow: true

  config.before do |example|
    next unless example.metadata[:rgb_lib] || example.metadata[:demo_flow]

    skip "./bin/regtest up required (RGB Lightning Nodes unreachable)" unless RgbLibHelpers.rln_available?
  end
end
