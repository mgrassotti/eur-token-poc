//! MAT DLC library: unsigned contract construction, on-device adaptor signing,
//! and watchtower CET/refund completion **without party secret keys**.

pub mod curve;
pub mod ffi;
pub mod keys;
pub mod sign;

use anyhow::{anyhow, bail, Context, Result};
use bitcoin::consensus::encode::serialize_hex;
use bitcoin::{Amount, Network, OutPoint, ScriptBuf};
use dlc::{create_dlc_transactions, DlcTransactions, Payout, PartyParams, TxInputInfo};
use secp256k1_zkp::{All, PublicKey, Secp256k1, SecretKey};
use serde::{Deserialize, Serialize};

use crate::curve::{announcement_digits, build_range_payouts, parse_announcement};
use crate::sign::{
    hex_pk, parse_address, parse_pk, random_serial, sign_adaptor, RangePayoutJson, SignPackage,
};

pub const MAX_WITNESS_LEN: usize = 107;

#[derive(Debug, Clone)]
pub struct BuildInput {
    pub txid: bitcoin::Txid,
    pub vout: u32,
    pub amount_sats: u64,
}

#[derive(Debug, Clone)]
pub struct BuildRequest {
    pub oracle_announcement: String,
    pub offer_collateral_sats: u64,
    pub accept_collateral_sats: u64,
    pub fee_rate_sats_vb: u64,
    pub rounding_buckets: u64,
    pub points: Vec<(i64, i64)>,
    pub peg_inputs: Vec<BuildInput>,
    pub investor_inputs: Vec<BuildInput>,
    pub peg_change_address: String,
    pub investor_change_address: String,
    pub peg_payout_address: String,
    pub investor_payout_address: String,
    pub peg_fund_pubkey: String,
    pub investor_fund_pubkey: String,
    pub refund_locktime: u32,
    pub cet_lock_time: u32,
    pub network: Network,
}

pub struct BuiltContract {
    pub dlc_txs: DlcTransactions,
    pub sign_package: SignPackage,
    pub funding_txid: String,
    pub funding_vout: u64,
    pub funding_tx_hex: String,
    pub funding_script: ScriptBuf,
    pub fund_value: Amount,
    pub peg_pk: PublicKey,
    pub investor_pk: PublicKey,
    pub peg_payout_spk: ScriptBuf,
    pub investor_payout_spk: ScriptBuf,
    pub refund_lock_time: u32,
    pub base: usize,
    pub points: Vec<(i64, i64)>,
    pub total: i64,
}

fn party_inputs(inputs: &[BuildInput]) -> (Vec<TxInputInfo>, u64) {
    let infos = inputs
        .iter()
        .map(|i| TxInputInfo {
            outpoint: OutPoint {
                txid: i.txid,
                vout: i.vout,
            },
            max_witness_len: MAX_WITNESS_LEN,
            redeem_script: ScriptBuf::new(),
            serial_id: random_serial(),
        })
        .collect();
    let amount = inputs.iter().map(|i| i.amount_sats).sum();
    (infos, amount)
}

pub fn build_unsigned_contract(req: &BuildRequest) -> Result<BuiltContract> {
    if req.peg_inputs.is_empty() || req.investor_inputs.is_empty() {
        bail!("peg_inputs and investor_inputs are required and must be non-empty");
    }
    let ann = parse_announcement(&req.oracle_announcement)?;
    let (base, nb_digits) = announcement_digits(&ann)?;
    let total = req.offer_collateral_sats + req.accept_collateral_sats;
    let peg_pk = parse_pk(&req.peg_fund_pubkey)?;
    let investor_pk = parse_pk(&req.investor_fund_pubkey)?;
    let peg_change_spk = parse_address(&req.peg_change_address, req.network)?;
    let investor_change_spk = parse_address(&req.investor_change_address, req.network)?;
    let peg_payout_spk = parse_address(&req.peg_payout_address, req.network)?;
    let investor_payout_spk = parse_address(&req.investor_payout_address, req.network)?;

    let (peg_input_infos, peg_input_amount) = party_inputs(&req.peg_inputs);
    let (investor_input_infos, investor_input_amount) = party_inputs(&req.investor_inputs);
    let refund_lock_time = req.refund_locktime.max(req.cet_lock_time.saturating_add(2));

    let offer_params = PartyParams {
        fund_pubkey: peg_pk,
        change_script_pubkey: peg_change_spk,
        change_serial_id: random_serial(),
        payout_script_pubkey: peg_payout_spk.clone(),
        payout_serial_id: random_serial(),
        inputs: peg_input_infos,
        input_amount: Amount::from_sat(peg_input_amount),
        collateral: Amount::from_sat(req.offer_collateral_sats),
    };
    let accept_params = PartyParams {
        fund_pubkey: investor_pk,
        change_script_pubkey: investor_change_spk,
        payout_script_pubkey: investor_payout_spk.clone(),
        payout_serial_id: random_serial(),
        change_serial_id: random_serial(),
        inputs: investor_input_infos,
        input_amount: Amount::from_sat(investor_input_amount),
        collateral: Amount::from_sat(req.accept_collateral_sats),
    };

    let range_payouts = build_range_payouts(
        &req.points,
        total,
        base,
        nb_digits,
        req.rounding_buckets,
    );
    let payouts: Vec<Payout> = range_payouts.iter().map(|r| r.payout.clone()).collect();
    let dlc_txs = create_dlc_transactions(
        &offer_params,
        &accept_params,
        &payouts,
        refund_lock_time,
        req.fee_rate_sats_vb,
        0,
        req.cet_lock_time,
        random_serial(),
    )
    .map_err(|e| anyhow!("create_dlc_transactions: {:?}", e))?;

    let funding_script = dlc_txs.funding_script_pubkey.clone();
    let fund_value = dlc_txs.get_fund_output().value;
    let funding_txid = dlc_txs.fund.compute_txid().to_string();
    let funding_tx_hex = serialize_hex(&dlc_txs.fund);
    let fund_vout = dlc_txs.get_fund_output_index() as u64;

    let sign_package = SignPackage {
        funding_script_hex: hex::encode(funding_script.as_bytes()),
        fund_value_sats: fund_value.to_sat(),
        refund_tx_hex: serialize_hex(&dlc_txs.refund),
        refund_lock_time,
        cets: dlc_txs.cets.iter().map(serialize_hex).collect(),
        range_payouts: range_payouts.iter().map(RangePayoutJson::from).collect(),
        oracle_announcement: req.oracle_announcement.clone(),
        peg_fund_pubkey: hex_pk(&peg_pk),
        investor_fund_pubkey: hex_pk(&investor_pk),
        peg_payout_address: req.peg_payout_address.clone(),
        investor_payout_address: req.investor_payout_address.clone(),
        base,
        nb_digits,
    };

    Ok(BuiltContract {
        dlc_txs,
        sign_package,
        funding_txid,
        funding_vout: fund_vout,
        funding_tx_hex,
        funding_script,
        fund_value,
        peg_pk,
        investor_pk,
        peg_payout_spk,
        investor_payout_spk,
        refund_lock_time,
        base,
        points: req.points.clone(),
        total: total as i64,
    })
}

/// Test/regtest helper: adaptor-sign both sides with provided seckeys.
pub fn auto_sign_both(
    secp: &Secp256k1<All>,
    package: &SignPackage,
    peg_sk: &SecretKey,
    investor_sk: &SecretKey,
) -> Result<(sign::PartySignatures, sign::PartySignatures)> {
    let offer = sign_adaptor(secp, peg_sk, package).context("sign offerer")?;
    let accept = sign_adaptor(secp, investor_sk, package).context("sign acceptor")?;
    Ok((offer, accept))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FundKeysJson {
    pub secret_hex: String,
    pub pubkey_hex: String,
}
