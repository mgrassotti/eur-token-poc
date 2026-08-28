# frozen_string_literal: true

require "rails_helper"

# Reproduces the mobile anonymous accept + funding sign round against regtest + DLC:
# create → accept → both funding_signatures → funded (not rolled back / hidden).
RSpec.describe "Anonymous deal accept (regtest)", :regtest, :dlc_integration, type: :request, skip: "MVP savings: accept is replaced by automatic matching" do
  def bitcoind_available?
    L1::Bitcoind::Client.new.available?
  end

  def client
    @client ||= L1::Bitcoind::Client.new
  end

  def with_temp_wallet
    name = "anon_accept_#{SecureRandom.hex(4)}"
    client.call("createwallet", name, false, false, "", false, true)
    wallet = client.with_wallet(name)
    yield wallet, name
  ensure
    begin
      client.call("unloadwallet", name)
    rescue L1::Bitcoind::Error
      nil
    end
  end

  def fund_address!(address, amount_sats)
    L1::FundReceiveAddressService.call(address: address, amount_sats: amount_sats)
  end

  def commitment_psbt_for!(wallet, required_sats)
    utxos = wallet.call("listunspent", 1, 9_999_999)
    raise "no utxos" if utxos.empty?

    selected = []
    total = 0
    utxos.sort_by { |u| -u.fetch("amount").to_d }.each do |utxo|
      selected << utxo
      total += (utxo.fetch("amount").to_d * 100_000_000).to_i
      break if total >= required_sats
    end
    raise "insufficient utxos" if total < required_sats

    change = wallet.call("getrawchangeaddress", "bech32")
    send_sats = [required_sats - 500, 546].max
    inputs = selected.map { |u| { "txid" => u["txid"], "vout" => u["vout"] } }
    outputs = { change => send_sats / 100_000_000.0 }
    hex = client.call("createrawtransaction", inputs, outputs)
    psbt = client.call("converttopsbt", hex, false)
    descriptors = selected.filter_map do |u|
      addr = u["address"]
      next if addr.blank?

      info = client.call("getdescriptorinfo", "addr(#{addr})")
      { "desc" => info.fetch("descriptor"), "range" => 0 }
    end
    client.call("utxoupdatepsbt", psbt, descriptors)
  end

  def coin_inputs(wallet, required_sats)
    utxos = wallet.call("listunspent", 1, 9_999_999)
    selected = []
    total = 0
    utxos.sort_by { |u| -u.fetch("amount").to_d }.each do |utxo|
      selected << {
        txid: utxo.fetch("txid"),
        vout: utxo.fetch("vout"),
        amount_sats: (utxo.fetch("amount").to_d * 100_000_000).to_i
      }
      total += selected.last[:amount_sats]
      break if total >= required_sats
    end
    raise "insufficient investor utxos" if total < required_sats

    selected
  end

  def sign_psbt!(wallet, psbt)
    result = wallet.call("walletprocesspsbt", psbt, true, "ALL")
    result.fetch("psbt")
  end

  before do
    skip "Avvia bitcoind regtest: ./bin/regtest up" unless bitcoind_available?
    skip "Oracle DLC non raggiungibile (#{Dlc::Config.oracle_url})" unless Dlc::Config.oracle_client.available?
    skip "Nodo DLC non raggiungibile (#{Dlc::Config.node_url})" unless Dlc::NodeClient.default.available?

    MarketRate.current.update!(btc_eur_per_btc: 50_000)
    L1::RegtestHarness.new(wallet_name: L1::SHARED_REGTEST_WALLET).ensure_chain_ready!
  end

  it "accepts, stays listed while awaiting signatures, then funds after both parties sign" do
    amount_eur_cents = 100_000
    peg = 50_000
    required_borrower = Budgets::ReserveRequirement.borrower_required_sats_for(amount_eur_cents, peg)
    required_investor = BtcConversion.eur_cents_to_sats(amount_eur_cents, peg) +
                        Dlc::ContractSetupService::FUNDING_FEE_BUFFER_SATS

    with_temp_wallet do |borrower_wallet, _borrower_name|
      borrower_address = borrower_wallet.call("getnewaddress", "", "bech32")
      fund_address!(borrower_address, required_borrower + 50_000)
      commitment_psbt = commitment_psbt_for!(borrower_wallet, required_borrower)

      with_temp_wallet do |investor_wallet, _investor_name|
        investor_address = investor_wallet.call("getnewaddress", "", "bech32")
        fund_address!(investor_address, required_investor + 50_000)
        investor_inputs = coin_inputs(investor_wallet, required_investor)
        investor_change = investor_wallet.call("getrawchangeaddress", "bech32")

        post "/api/v1/deals", params: {
          deal: {
            amount_eur_cents: amount_eur_cents,
            period_start: Date.current.iso8601,
            period_end: (Date.current + 30).iso8601,
            funding_address: borrower_address,
            commitment_psbt: commitment_psbt,
            borrower_name: "AliceMobile"
          }
        }, as: :json

        expect(response).to have_http_status(:created)
        deal_id = JSON.parse(response.body).fetch("id")

        post "/api/v1/deals/#{deal_id}/accept", params: {
          funding_address: investor_address,
          investor_name: "BobMobile",
          investor_inputs: investor_inputs,
          investor_change_address: investor_change,
          investor_payout_address: investor_wallet.call("getnewaddress", "dlc_settlement", "bech32"),
          investor_identity_pubkey: "02#{"b" * 64}",
          peg_change_address: borrower_address,
          peg_identity_pubkey: "02#{"a" * 64}"
        }, as: :json

        expect(response).not_to have_http_status(:internal_server_error)
        expect(response).to have_http_status(:ok), -> { response.body }

        body = JSON.parse(response.body)
        expect(body["status"]).to eq("active")
        expect(body["awaiting_funding_signatures"]).to be(true)
        expect(body["funding_psbt"]).to be_present
        expect(body["investor_funding_address"]).to eq(investor_address)
        funding_psbt = body["funding_psbt"]

        # Not rolled back: still marketplace-visible while awaiting signatures.
        get "/api/v1/deals", as: :json
        expect(response).to have_http_status(:ok)
        listed = JSON.parse(response.body).fetch("deals")
        listed_deal = listed.find { |d| d["id"] == deal_id }
        expect(listed_deal).to be_present, "deal disappeared from GET /deals after accept"
        expect(listed_deal["awaiting_funding_signatures"]).to be(true)
        expect(listed_deal["status"]).to eq("active")

        budget = Budget.find(deal_id)
        expect(budget).to be_active
        expect(budget.escrow_txid).to be_blank
        expect(budget.dlc_contract).to be_announced

        # Investor signs first (as mobile does on accept).
        investor_signed = sign_psbt!(investor_wallet, funding_psbt)
        post "/api/v1/deals/#{deal_id}/funding_signature", params: {
          funding_address: investor_address,
          signed_psbt: investor_signed
        }, as: :json
        expect(response).to have_http_status(:ok), -> { response.body }
        after_investor = JSON.parse(response.body)
        expect(after_investor["investor_funding_signed"]).to be(true)
        expect(after_investor["borrower_funding_signed"]).to be(false)
        expect(after_investor["awaiting_funding_signatures"]).to be(true)
        expect(Budget.find(deal_id)).to be_active

        # Still listed for Alice to find and sign.
        get "/api/v1/deals", as: :json
        expect(JSON.parse(response.body).fetch("deals").map { |d| d["id"] }).to include(deal_id)

        # Borrower completes the sign round → broadcast + not reverted.
        borrower_signed = sign_psbt!(borrower_wallet, after_investor.fetch("funding_psbt"))
        post "/api/v1/deals/#{deal_id}/funding_signature", params: {
          funding_address: borrower_address,
          signed_psbt: borrower_signed
        }, as: :json
        expect(response).to have_http_status(:ok), -> { response.body }

        funded = JSON.parse(response.body)
        expect(funded["status"]).to eq("active")
        expect(funded["awaiting_funding_signatures"]).to be(false)

        budget.reload
        expect(budget).to be_active
        expect(budget.escrow_txid).to be_present
        expect(budget.l1_multisig_provisioned?).to be(true)
        expect(budget.dlc_contract.reload).to be_funded
      end
    end
  end
end
