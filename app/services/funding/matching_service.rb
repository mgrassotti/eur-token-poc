# frozen_string_literal: true

module Funding
  # FIFO matcher: one queued saver + one queued investor with enough EUR capacity.
  # Each fill opens a bilateral DLC. Users do not pick counterparties.
  class MatchingService
    class Error < StandardError; end

    Result = Data.define(:budgets)

    def self.call
      new.call
    end

    def call
      budgets = []

      loop do
        saver, investor = next_pair
        break unless saver && investor

        budgets << open_contract!(saver, investor)
      rescue ActivateFailure => e
        Rails.logger.warn("Funding match skipped: #{e.message}")
        break
      end

      Result.new(budgets: budgets)
    end

    private

    class ActivateFailure < StandardError; end

    def next_pair
      FundingRequest.saver.matchable.order(:created_at).find_each do |saver|
        investor = FundingRequest.investor.matchable.order(:created_at).detect do |candidate|
          candidate.user_id != saver.user_id &&
            candidate.remaining_eur_cents >= saver.amount_eur_cents &&
            candidate.ready_to_match?
        end
        return [saver, investor] if investor && saver.ready_to_match?
      end
      [nil, nil]
    end

    def open_contract!(saver, investor)
      period_start = Date.current
      period_end = period_start >> CreateRequest::TERM_MONTHS
      peg = MarketRate.current.btc_eur_per_btc

      budget = nil
      ActiveRecord::Base.transaction do
        saver.lock!
        investor.lock!
        raise ActivateFailure, "saver no longer matchable" unless saver.ready_to_match?
        raise ActivateFailure, "investor no longer matchable" unless investor.ready_to_match?

        budget = Budgets::CreateService.call(
          borrower: saver.user,
          amount_eur_cents: saver.amount_eur_cents,
          period_start: period_start,
          period_end: period_end,
          funding_address: saver.receive_address,
          skip_fund_check: true
        )

        budget.update!(
          rate_bps_monthly: CreateRequest::RATE_BPS,
          saver_payout_mode: saver.payout_mode,
          saver_payout_iban: saver.payout_iban,
          saver_payout_address: saver_payout_address(saver),
          investor_payout_mode: investor.payout_mode,
          saver_funding_request_id: saver.id,
          investor_funding_request_id: investor.id
        )
      end

      funding = Budgets::FundingParams.new(
        peg_inputs: saver.funding_inputs_list,
        investor_inputs: investor.funding_inputs_list,
        peg_change_address: saver.change_address.presence || saver.receive_address,
        investor_change_address: investor.change_address.presence || investor.receive_address,
        investor_payout_address: investor.receive_address,
        peg_identity_pubkey: saver.identity_pubkey.presence || "02#{"a" * 64}",
        investor_identity_pubkey: investor.identity_pubkey.presence || "02#{"b" * 64}"
      )

      verify = L1::Bitcoind::Client.new.available?
      Budgets::ActivateService.call(
        budget: budget,
        investor: investor.user,
        funding: funding,
        verify_utxos: verify
      )

      mark_matched!(saver, investor, budget.reload, peg)
      budget
    rescue Budgets::CreateService::Error, Budgets::ActivateService::Error,
           Budgets::FundingParams::Error, L1::ProvisionEscrowService::Error,
           Dlc::ContractSetupService::Error => e
      budget&.destroy
      raise ActivateFailure, e.message
    end

    def saver_payout_address(saver)
      return BankAccount.default.btc_receive_address if saver.eur?

      saver.receive_address
    end

    def mark_matched!(saver, investor, budget, _peg)
      saver.update!(status: :matched, budget: budget)
      leftover = investor.remaining_eur_cents - saver.amount_eur_cents
      if leftover.positive?
        investor.update!(
          remaining_eur_cents: leftover,
          funding_inputs: nil,
          status: :awaiting_deposit
        )
      else
        investor.update!(status: :matched, remaining_eur_cents: 0, budget: budget)
      end
    end
  end
end
