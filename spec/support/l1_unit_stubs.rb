# frozen_string_literal: true

module L1UnitStubs
  L1_INTEGRATION_PATH = %r{
    spec/integration/l1/|
    spec/integration/demo_end_to_end_flow_spec\.rb|
    spec/services/l1/(deposit_reserve|settlement_spend)_service_spec\.rb
  }x

  def l1_integration_spec?(example)
    example.metadata[:l1_integration] == true || example.file_path.match?(L1_INTEGRATION_PATH)
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
    next if l1_integration_spec?(example)

    stub_l1_unit_operations!
  end
end
