# frozen_string_literal: true

module Api
  module V1
    class AuthController < BaseController
      skip_before_action :authenticate_api_user!, only: :login

      def login
        user = User.find_by(email: login_params[:email].to_s.strip.downcase)

        if user&.authenticate(login_params[:password])
          render json: {
            token: Api::AuthToken.generate(user),
            user: user_payload(user)
          }
        else
          render json: { error: "invalid_credentials" }, status: :unauthorized
        end
      end

      def show
        render json: { user: user_payload(current_user) }
      end

      private

      def login_params
        params.permit(:email, :password)
      end

      def user_payload(user)
        {
          id: user.id,
          name: user.name,
          email: user.email,
          admin: user.admin?
        }
      end
    end
  end
end
