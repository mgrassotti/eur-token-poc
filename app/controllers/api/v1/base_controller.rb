# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods

      before_action :authenticate_api_user!

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not_found" }, status: :not_found
      end

      rescue_from ActionController::ParameterMissing do |e|
        render json: { error: "parameter_missing", detail: e.message }, status: :unprocessable_entity
      end

      private

      attr_reader :current_user

      def authenticate_api_user!
        @current_user = user_from_bearer_token
        return if @current_user

        render json: { error: "unauthorized" }, status: :unauthorized
      end

      def user_from_bearer_token
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")&.strip
        return if token.blank?

        Api::AuthToken.verify(token)
      end

      def require_admin!
        return if current_user&.admin?

        render json: { error: "forbidden" }, status: :forbidden
      end
    end
  end
end
