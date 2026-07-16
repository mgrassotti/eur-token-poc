# frozen_string_literal: true

module Api
  module V1
    module Integration
      # Dev/test-only hooks for Flutter integration tests (simulates admin UI actions).
      class BaseController < ActionController::API
        before_action :require_dev_or_test!
        before_action :require_integration_secret!

        private

        def require_dev_or_test!
          return if Rails.env.development? || Rails.env.test?

          render json: { error: "forbidden" }, status: :forbidden
        end

        def require_integration_secret!
          expected = ENV.fetch("INTEGRATION_TEST_SECRET", "dev-integration-secret")
          provided = request.headers["X-Integration-Secret"].to_s

          return if ActiveSupport::SecurityUtils.secure_compare(expected, provided)

          render json: { error: "forbidden" }, status: :forbidden
        end
      end
    end
  end
end
