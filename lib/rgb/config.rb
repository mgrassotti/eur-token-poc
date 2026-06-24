# frozen_string_literal: true

module Rgb
  module Config
    ISSUER_WALLET_ID = "rgb_issuer"

    def self.sidecar_url
      ENV.fetch("RGB_SIDECAR_URL", "http://127.0.0.1:3030")
    end

    def self.ensure_sidecar!
      return if SidecarClient.instance.available?

      raise SidecarClient::Error,
            "RGB sidecar required at #{sidecar_url} — run ./bin/regtest up"
    end

    def self.wallet_id_for(user)
      "user_#{user.id}"
    end
  end
end
