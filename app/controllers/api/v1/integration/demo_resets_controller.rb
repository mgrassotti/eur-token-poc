# frozen_string_literal: true

module Api
  module V1
    module Integration
      class DemoResetsController < BaseController
        def create
          DemoData::ResetService.call
          render json: { schema_version: 1, status: "reset" }
        end
      end
    end
  end
end
