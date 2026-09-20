# frozen_string_literal: true

module L1UnitStubs
  L1_INTEGRATION_PATH = %r{
    spec/integration/l1/|
    spec/integration/rgb_lib_transfer_spec\.rb|
    spec/integration/demo_end_to_end_flow_spec\.rb
  }x

  def l1_integration_spec?(example)
    example.metadata[:l1_integration] == true || example.file_path.match?(L1_INTEGRATION_PATH)
  end

  def rgb_lib_spec?(example)
    example.metadata[:rgb_lib] == true
  end

  # Specs that drive the real L1 stack (integration/regtest/system/demo): they
  # must NOT receive L1 unit stubs, otherwise stubbed services swallow the
  # behaviour under test. RGB may still be mirrored (see real_rgb_spec?).
  def real_l1_spec?(example)
    l1_integration_spec?(example) ||
      example.metadata[:regtest] == true ||
      example.metadata[:demo_flow] == true ||
      example.metadata[:type] == :system
  end

  # Specs that assert on the real RGB stack (RLN nodes): only these skip the RGB
  # mirror. L1-focused regtest specs keep the RGB mirror so budget activation can
  # issue a mock asset without requiring a configured/funded RLN node per user.
  def real_rgb_spec?(example)
    rgb_lib_spec?(example) || example.metadata[:demo_flow] == true
  end

  def stub_l1_provisioned!(budget)
    budget.update!(
      peg_party_pubkey: budget.peg_party_pubkey.presence || "02#{"a" * 64}",
      investor_pubkey: budget.investor_pubkey.presence || "02#{"b" * 64}",
      escrow_txid: budget.escrow_txid.presence || "deadbeef" * 8,
      escrow_vout: budget.escrow_vout || 0,
      recovery_package: budget.recovery_package.presence || { "version" => 1, "escrow" => { "address" => "bcrt1stub" } }
    )
    seed_rgb_genesis!(budget)
    seed_dlc_contract!(budget)
  end

  # DLC is the settlement mechanism: activation funds a 2-of-2 DLC. Unit specs
  # seed a funded contract so Settlements::ExecuteService can run offline (the
  # oracle attestation + CET broadcast are stubbed by stub_dlc_settlement!).
  def seed_dlc_contract!(budget)
    return if budget.dlc_contract.present?

    DlcContract.create!(
      budget: budget,
      oracle_event_id: "deal-#{budget.id}",
      oracle_announcement: "stub",
      ddk_contract_id: "c-#{budget.id}",
      funding_txid: "ab" * 32,
      funding_vout: 0,
      num_digits: 20,
      status: :funded
    )
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
    allow(Rgb::Config).to receive(:ensure_node!)

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

    allow(Rgb::TransferService).to receive(:call) do |budget:, from_user:, to_user:, amount_cents:, rgb_recipient_id: nil|
      Rgb::TransferResult.new(
        txid: "stub",
        recipient_id: rgb_recipient_id.presence || "rcp_stub",
        asset_id: budget.rgb_asset_id,
        amount: amount_cents
      )
    end
  end

  def stub_l1_unit_operations!
    allow_any_instance_of(L1::Bitcoind::Client).to receive(:available?).and_return(true)

    allow(L1::ProvisionEscrowService).to receive(:call) do |budget:, auto_sign_wallets: nil|
      budget.tap { |b| stub_l1_provisioned!(b) if b.persisted? && !b.l1_multisig_provisioned? }
    end

    allow(L1::UserWallet).to receive(:for) do |user|
      wallet = instance_double(L1::UserWallet, wallet_name: "user_#{user.id}")
      account = user.btc_account
      allow(wallet).to receive(:spendable_sats) { account.reload.balance_sats }
      allow(wallet).to receive(:sync_balance_to_account!) { account.reload }
      allow(wallet).to receive(:escrow_identity_wif) { account.escrow_identity_wif }
      allow(wallet).to receive(:identity_pubkey) { account.escrow_identity_pubkey }
      wallet
    end
  end

  # Specs that exercise the real DLC services (oracle/node clients + Ruby
  # services) must keep the real Dlc::SettlementService / Dlc::Distribution.
  def dlc_unit_spec?(example)
    example.file_path.match?(%r{spec/(services|lib|integration)/dlc/})
  end

  # Offline stub for the DLC settlement path used by Settlements::ExecuteService.
  # CET outputs follow FloorEUR; distribution echoes explicit holder targets.
  def stub_dlc_settlement!
    allow(Dlc::SettlementService).to receive(:call) do |budget:, end_btc_eur_rate:, **|
      @stub_settlement_end_rate = end_btc_eur_rate
      payoff = stub_floor_payoff(budget, end_btc_eur_rate)
      Dlc::SettlementService::Result.new(
        dlc_settlement: nil,
        cet_txid: "cet#{"0" * 61}",
        outcome: end_btc_eur_rate.to_i,
        peg_pot_sats: payoff.total_holder_sats,
        investor_sats: payoff.investor_remainder_sats
      )
    end

    allow(Dlc::Distribution).to receive(:call) do |budget:, peg_pot_sats:, shares: nil, holder_targets: nil, **|
      stub_dlc_distribution(budget:, holder_targets:, shares:, peg_pot_sats:)
    end
  end

  def stub_floor_payoff(budget, end_btc_eur_rate)
    token_accounts = budget.token_accounts.where("balance_cents > 0").order(:id).to_a
    height = budget.maturity_block_height || ChainState.block_height
    Payoffs::FloorEurCalculator.call(
      notional_eur_cents: budget.notional_eur_cents,
      notional_total_cents: budget.amount_eur_cents,
      holder_shares_cents: token_accounts.map(&:balance_cents),
      spot_eur_per_btc: end_btc_eur_rate,
      rate_bps_monthly: budget.rate_bps_monthly,
      months_elapsed: budget.months_elapsed(at_height: height),
      escrow_total_sats: budget.pool_sats
    )
  end

  def stub_dlc_distribution(budget:, holder_targets:, shares:, peg_pot_sats:)
    targets = if holder_targets
                holder_targets
              else
                stub_pro_rata_targets(peg_pot_sats, shares)
              end
    return [] if targets.empty?

    end_rate = @stub_settlement_end_rate || MarketRate.current.btc_eur_per_btc
    payoff = stub_floor_payoff(budget, end_rate)
    holder_total = targets.sum { |t| t[:sats] }
    dist_fee = Dlc::Distribution.fee_estimate(targets.size)
    investor_payout_sats = [payoff.investor_remainder_sats - dist_fee, 0].max
    txid = "dist#{"0" * 61}"

    package = budget.recovery_package&.deep_dup || {}
    package["dlc_distribution"] = {
      "txid" => txid,
      "peg_pot_sats" => holder_total,
      "investor_payout_sats" => investor_payout_sats,
      "investor_payout_address" => "bcrt1investor-stub",
      "payouts" => targets.map do |target|
        { "user_id" => target[:user].id, "sats" => target[:sats], "address" => "stub-#{target[:user].id}" }
      end
    }
    budget.update!(recovery_package: package)

    targets.map do |target|
      Dlc::Distribution::Payout.new(
        user: target[:user],
        sats: target[:sats],
        address: "stub-#{target[:user].id}",
        txid: txid
      )
    end
  end

  def stub_pro_rata_targets(peg_pot_sats, shares)
    return [] if shares.blank?

    total_cents = shares.sum { |s| Integer(s[:cents]) }
    return [] if total_cents.zero?

    assigned = 0
    shares[0..-2].filter_map do |share|
      cents = Integer(share[:cents])
      next if cents.zero?

      sats = (peg_pot_sats * cents) / total_cents
      assigned += sats
      { user: share[:user], sats: sats }
    end + begin
      last = shares.last
      cents = Integer(last[:cents])
      cents.positive? ? [{ user: last[:user], sats: peg_pot_sats - assigned }] : []
    end
  end
end

RSpec.configure do |config|
  config.include L1UnitStubs

  config.before do |example|
    stub_rgb_mirror! unless real_rgb_spec?(example)
  end

  config.before do |example|
    next if real_l1_spec?(example)

    stub_l1_unit_operations!
    stub_dlc_settlement! unless dlc_unit_spec?(example)
  end
end
