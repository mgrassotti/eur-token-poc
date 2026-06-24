# frozen_string_literal: true

module L1UnitStubs
  L1_INTEGRATION_PATH = %r{
    spec/integration/l1/|
    spec/integration/rgb_lib_transfer_spec\.rb|
    spec/integration/demo_end_to_end_flow_spec\.rb|
    spec/services/l1/(deposit_reserve|settlement_spend)_service_spec\.rb
  }x

  def l1_integration_spec?(example)
    example.metadata[:l1_integration] == true || example.file_path.match?(L1_INTEGRATION_PATH)
  end

  def rgb_lib_spec?(example)
    example.metadata[:rgb_lib] == true
  end

  def real_rgb_spec?(example)
    rgb_lib_spec?(example) || example.metadata[:demo_flow] == true
  end

  def stub_l1_provisioned!(budget)
    budget.update!(
      peg_party_pubkey: "02#{"a" * 64}",
      investor_pubkey: "02#{"b" * 64}",
      bot_pubkey: "02#{"c" * 64}",
      escrow_txid: "deadbeef" * 8,
      escrow_vout: 0,
      recovery_package: { "version" => 1, "escrow" => { "address" => "bcrt1stub" } }
    )
    seed_rgb_genesis!(budget)
  end

  def seed_rgb_genesis!(budget)
    return if budget.rgb_assignments.exists?
    return unless budget.borrower

    budget.update!(rgb_asset_id: "rgb_stub_#{budget.id}") if budget.rgb_asset_id.blank?

    pubkey = budget.borrower.btc_account&.escrow_identity_pubkey || "02#{"a" * 64}"
    RgbAssignment.create!(
      budget: budget,
      user: budget.borrower,
      assignment_id: SecureRandom.uuid,
      holder_pubkey: pubkey,
      notional_share_cents: budget.amount_eur_cents,
      rgb_asset_id: budget.rgb_asset_id
    )

    TokenAccount.find_or_create_by!(budget: budget, user: budget.borrower) do |account|
      account.balance_cents = budget.amount_eur_cents
    end
  end

  def stub_rgb_mirror!
    allow(Rgb::IssueService).to receive(:call) do |budget:|
      budget.update!(rgb_asset_id: "rgb_stub_#{budget.id}") if budget.rgb_asset_id.blank?
      rgb_result = Rgb::IssueResult.new(
        asset_id: budget.rgb_asset_id,
        ticker: "E#{budget.id}"[0, 8],
        name: "FloorEUR deal #{budget.id}",
        recipient_id: "rcp_stub",
        issue_txid: "stub",
        amount_cents: budget.amount_eur_cents
      )
      Rgb::ProjectionService.apply_issue!(budget:, rgb_result:)
    end

    allow(Rgb::TransferService).to receive(:call) do |budget:, from_user:, to_user:, amount_cents:|
      Rgb::TransferResult.new(
        txid: "stub",
        recipient_id: "rcp_stub",
        asset_id: budget.rgb_asset_id,
        amount: amount_cents
      )
    end
  end

  def stub_l1_unit_operations!
    allow(L1::ProvisionEscrowService).to receive(:call) do |budget:|
      budget.tap { |b| stub_l1_provisioned!(b) if b.persisted? && !b.l1_multisig_provisioned? }
    end

    allow(L1::SettlementSpendService).to receive(:call)
    allow(L1::SettlementPsbtService).to receive(:build) do |budget:, payoff:, holder_payouts:, co_signer: L1::SettlementPsbtService::DEFAULT_CO_SIGNER|
      L1::SettlementPsbtService::SettlementPsbt.new(
        budget: budget,
        payoff: payoff,
        holder_payouts: [],
        raw_hex: "00",
        psbt: "cHNidP8B",
        hex: nil,
        complete: false,
        signatures_applied: [],
        co_signer: co_signer
      )
    end
    allow(L1::SettlementPsbtService).to receive(:sign!) { |draft, _role| draft }
    allow(L1::SettlementPsbtService).to receive(:broadcast!) { "deadbeef" * 8 }
    allow(L1::SettlementPsbtTemplateService).to receive(:call) { |budget:, **| budget }

    allow(L1::UserWallet).to receive(:for) do |user|
      wallet = instance_double(L1::UserWallet, wallet_name: "user_#{user.id}")
      account = user.btc_account
      allow(wallet).to receive(:spendable_sats) { account.reload.balance_sats }
      allow(wallet).to receive(:sync_balance_to_account!) { account.reload }
      allow(wallet).to receive(:escrow_identity_wif) { account.escrow_identity_wif }
      allow(wallet).to receive(:identity_pubkey) { account.escrow_identity_pubkey }
      wallet
    end

    allow(L1::SyncReserveBalanceService).to receive(:call) { |user:| user.btc_account.reload }
  end
end

RSpec.configure do |config|
  config.include L1UnitStubs

  config.before do |example|
    stub_rgb_mirror! unless real_rgb_spec?(example)
  end

  config.before do |example|
    next if l1_integration_spec?(example) || real_rgb_spec?(example)

    stub_l1_unit_operations!
  end
end
