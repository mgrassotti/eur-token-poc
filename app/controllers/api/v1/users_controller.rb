# frozen_string_literal: true

module Api
  module V1
    class UsersController < BaseController
      def index
        users = User.where(admin: false).where.not(id: current_user.id).order(:name)

        render json: {
          schema_version: 1,
          users: users.map { |user| { id: user.id, name: user.name, email: user.email } }
        }
      end
    end
  end
end
