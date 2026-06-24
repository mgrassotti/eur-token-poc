# frozen_string_literal: true

module RgbLibHelpers
  COMPOSE_FILE = Rails.root.join("docker-compose.regtest.yml").to_s

  module_function

  def reset_rgb_wallet_data!
    reset_via_sidecar!
  rescue Rgb::SidecarClient::Error
    reset_via_docker_exec!
  end

  def reset_via_sidecar!
    Rgb::SidecarClient.instance.reset_all_wallets!
  end

  def reset_via_docker_exec!
    success = system(
      "docker", "compose", "-f", COMPOSE_FILE,
      "exec", "-T", "rgb-sidecar",
      "sh", "-c", "rm -rf /data/wallets/*",
      out: File::NULL, err: File::NULL
    )
    raise "RGB wallet reset failed (rebuild sidecar or run ./bin/regtest up)" unless success
  end
end

RSpec.configure do |config|
  config.before do |example|
    next unless example.metadata[:rgb_lib] || example.metadata[:demo_flow]

    unless Rgb::SidecarClient.instance.available?
      skip "./bin/regtest up required (RGB sidecar unreachable)"
    end

    RgbLibHelpers.reset_rgb_wallet_data!
  end
end
