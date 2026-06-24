# frozen_string_literal: true

module Rgb
  IssueResult = Data.define(:asset_id, :ticker, :name, :recipient_id, :issue_txid, :amount_cents)
end
