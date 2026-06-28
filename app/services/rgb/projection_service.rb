# frozen_string_literal: true

module Rgb
  # Proiezione DB dopo operazioni RGB on-chain (unico writer di saldi ledger).
  class ProjectionService
    class Error < StandardError; end

    def self.apply_issue!(budget:, rgb_result:)
      new(budget:, rgb_result:).apply_issue!
    end

    def self.apply_transfer!(budget:, from_user:, to_user:, amount_cents:, rgb_result:)
      new(
        budget:,
        from_user:,
        to_user:,
        amount_cents:,
        rgb_result:
      ).apply_transfer!
    end

    def self.apply_redeem!(budget:, holder:)
      new(budget:, from_user: holder).apply_redeem!
    end

    def initialize(budget:, from_user: nil, to_user: nil, amount_cents: nil, rgb_result: nil)
      @budget = budget
      @from_user = from_user
      @to_user = to_user
      @amount_cents = amount_cents&.to_i
      @rgb_result = rgb_result
    end

    def apply_issue!
      ActiveRecord::Base.transaction do
        budget.update!(rgb_asset_id: rgb_result.asset_id)

        assignment = RgbAssignment.find_or_initialize_by(budget: budget, user: budget.borrower)
        assignment.assign_attributes(
          assignment_id: SecureRandom.uuid,
          holder_pubkey: HolderIdentity.pubkey_for(budget.borrower),
          notional_share_cents: rgb_result.amount_cents,
          rgb_asset_id: rgb_result.asset_id,
          rgb_recipient_id: rgb_result.recipient_id,
          parent_assignment_id: nil
        )
        assignment.save!

        account = TokenAccount.find_or_initialize_by(budget: budget, user: budget.borrower)
        account.balance_cents = rgb_result.amount_cents
        account.save!

        persist_issue_recovery_package!(assignment:)

        assignment
      end
    end

    def apply_transfer!
      ActiveRecord::Base.transaction do
        from_account = budget.token_accounts.lock.find_by!(user: from_user)
        to_account = budget.token_accounts.lock.find_or_create_by!(user: to_user)

        if from_account.balance_cents < amount_cents
          raise Error, "Proiezione: saldo token insufficiente (#{from_account.balance_cents} < #{amount_cents})"
        end

        from_account.update!(balance_cents: from_account.balance_cents - amount_cents)
        to_account.update!(balance_cents: to_account.balance_cents + amount_cents)

        transfer = TokenTransfer.create!(
          budget: budget,
          from_user: from_user,
          to_user: to_user,
          amount_cents: amount_cents,
          rgb_transfer_txid: rgb_result.txid,
          rgb_consignment: consignment_payload
        )

        update_rgb_assignments!
        append_recovery_history!

        transfer
      end
    end

    # Cache-only: dopo la redemption RGB on-chain azzera la proiezione DB del holder
    # (token account + rgb_assignment) per allinearla alla verità RGB del sidecar.
    def apply_redeem!
      ActiveRecord::Base.transaction do
        budget.token_accounts.lock.where(user: from_user).find_each do |account|
          account.update!(balance_cents: 0)
        end
        budget.rgb_assignments.lock.where(user: from_user).find_each do |assignment|
          assignment.update!(notional_share_cents: 0)
        end
      end
    end

    private

    attr_reader :budget, :from_user, :to_user, :amount_cents, :rgb_result

    def persist_issue_recovery_package!(assignment:)
      package = (budget.recovery_package || {}).deep_dup
      package["consignment_rgb"] = {
        mode: "rgb-lib RGB20",
        asset_id: rgb_result.asset_id,
        assignment_id: assignment.assignment_id,
        notional_share: assignment.notional_share_cents,
        deal_id: budget.id,
        escrow_outpoint: budget.escrow_outpoint,
        issue_transfer_txid: rgb_result.issue_txid
      }
      budget.update!(recovery_package: package)
    end

    def consignment_payload
      {
        mode: "rgb-lib transfer",
        asset_id: rgb_result.asset_id,
        amount: rgb_result.amount,
        recipient_id: rgb_result.recipient_id,
        txid: rgb_result.txid
      }
    end

    def update_rgb_assignments!
      sender = budget.rgb_assignments.lock.find_by!(user: from_user)
      receiver = budget.rgb_assignments.lock.find_or_initialize_by(user: to_user)

      sender.update!(notional_share_cents: sender.notional_share_cents - amount_cents)
      receiver.assign_attributes(
        assignment_id: SecureRandom.uuid,
        holder_pubkey: HolderIdentity.pubkey_for(to_user),
        notional_share_cents: receiver.notional_share_cents.to_i + amount_cents,
        rgb_asset_id: budget.rgb_asset_id,
        rgb_recipient_id: rgb_result.recipient_id,
        parent_assignment_id: receiver.parent_assignment_id || sender.assignment_id
      )
      receiver.save!
    end

    def append_recovery_history!
      package = (budget.recovery_package || {}).deep_dup
      history = Array(package["consignment_rgb_transfers"])
      history << {
        txid: rgb_result.txid,
        from_user_id: from_user.id,
        to_user_id: to_user.id,
        amount: amount_cents
      }
      package["consignment_rgb_transfers"] = history
      budget.update!(recovery_package: package)
    end
  end
end
