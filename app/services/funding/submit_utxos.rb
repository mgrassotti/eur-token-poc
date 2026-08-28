# frozen_string_literal: true

module Funding
  class SubmitUtxos
    class Error < StandardError; end

    def self.call(request:, inputs:, change_address:, identity_pubkey: nil)
      new(request:, inputs:, change_address:, identity_pubkey:).call
    end

    def initialize(request:, inputs:, change_address:, identity_pubkey:)
      @request = request
      @inputs = Budgets::FundingParams.normalize_inputs(inputs)
      @change_address = change_address.to_s.strip
      @identity_pubkey = identity_pubkey.to_s.strip.presence
    end

    def call
      raise Error, "request is not awaiting coins" unless @request.awaiting_deposit? || @request.queued?
      raise Error, "funding_inputs required" if @inputs.empty?
      raise Error, "change_address required" if @change_address.blank?

      @request.update!(
        funding_inputs: @inputs,
        change_address: @change_address,
        identity_pubkey: @identity_pubkey || placeholder_pubkey,
        status: :queued
      )

      MatchingService.call
      @request.reload
    end

    private

    def placeholder_pubkey
      "02#{"c" * 64}"
    end
  end
end
