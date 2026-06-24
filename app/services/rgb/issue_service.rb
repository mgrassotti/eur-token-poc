# frozen_string_literal: true

module Rgb
  # Genesis RGB20 per il borrower dopo provision escrow (rgb-lib via sidecar).
  class IssueService
    class Error < StandardError; end

    def self.call(budget:)
      new(budget:).call
    end

    def initialize(budget:)
      @budget = budget
    end

    def call
      Config.ensure_sidecar!

      existing = budget.rgb_assignments.find_by(user: budget.borrower)
      return existing if budget.rgb_asset_id.present? && existing

      rgb_result = LibIssueService.call(budget:)
      ProjectionService.apply_issue!(budget:, rgb_result:)
    end

    private

    attr_reader :budget
  end
end
