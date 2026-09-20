//! Adaptor signing, CET completion without keys, and refund assembly.

use anyhow::{anyhow, bail, Context, Result};
use bitcoin::consensus::encode::{deserialize, serialize_hex};
use bitcoin::sighash::EcdsaSighashType;
use bitcoin::{Amount, ScriptBuf, Transaction, Witness};
use std::str::FromStr;
use dlc::{RangePayout, Payout};
use dlc_trie::multi_oracle_trie::MultiOracleTrie;
use dlc_trie::{DlcTrie, OracleNumericInfo};
use secp256k1_zkp::ecdsa::Signature;
use secp256k1_zkp::rand::{thread_rng, Rng};
use secp256k1_zkp::schnorr::Signature as SchnorrSig;
use secp256k1_zkp::{
    All, EcdsaAdaptorSignature, PublicKey, Scalar, Secp256k1, SecretKey,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::curve::{announcement_digits, parse_announcement, precompute_points};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RangePayoutJson {
    pub start: usize,
    pub count: usize,
    pub offer_sats: u64,
    pub accept_sats: u64,
}

impl From<&RangePayout> for RangePayoutJson {
    fn from(r: &RangePayout) -> Self {
        Self {
            start: r.start,
            count: r.count,
            offer_sats: r.payout.offer.to_sat(),
            accept_sats: r.payout.accept.to_sat(),
        }
    }
}

impl From<&RangePayoutJson> for RangePayout {
    fn from(r: &RangePayoutJson) -> Self {
        RangePayout {
            start: r.start,
            count: r.count,
            payout: Payout {
                offer: Amount::from_sat(r.offer_sats),
                accept: Amount::from_sat(r.accept_sats),
            },
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignPackage {
    pub funding_script_hex: String,
    pub fund_value_sats: u64,
    pub refund_tx_hex: String,
    pub refund_lock_time: u32,
    pub cets: Vec<String>,
    pub range_payouts: Vec<RangePayoutJson>,
    pub oracle_announcement: String,
    pub peg_fund_pubkey: String,
    pub investor_fund_pubkey: String,
    pub peg_payout_address: String,
    pub investor_payout_address: String,
    pub base: usize,
    pub nb_digits: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PartySignatures {
    pub adaptor_sigs: Vec<String>,
    pub refund_sig: String,
}

pub fn hex_pk(pk: &PublicKey) -> String {
    hex::encode(pk.serialize())
}

pub fn parse_pk(hex_str: &str) -> Result<PublicKey> {
    let bytes = hex::decode(hex_str.trim()).context("decode pubkey hex")?;
    PublicKey::from_slice(&bytes).map_err(|e| anyhow!("pubkey: {e}"))
}

pub fn tx_from_hex(hex_str: &str) -> Result<Transaction> {
    let bytes = hex::decode(hex_str.trim()).context("decode tx hex")?;
    deserialize(&bytes).context("deserialize tx")
}

pub fn script_from_hex(hex_str: &str) -> Result<ScriptBuf> {
    let bytes = hex::decode(hex_str.trim()).context("decode script hex")?;
    Ok(ScriptBuf::from_bytes(bytes))
}

pub fn adaptor_to_hex(sig: &EcdsaAdaptorSignature) -> String {
    hex::encode(sig.as_ref())
}

pub fn adaptor_from_hex(hex_str: &str) -> Result<EcdsaAdaptorSignature> {
    let bytes = hex::decode(hex_str.trim()).context("decode adaptor sig")?;
    EcdsaAdaptorSignature::from_slice(&bytes).map_err(|e| anyhow!("adaptor sig: {e}"))
}

pub fn ecdsa_to_hex(sig: &Signature) -> String {
    hex::encode(sig.serialize_compact())
}

pub fn ecdsa_from_hex(hex_str: &str) -> Result<Signature> {
    let bytes = hex::decode(hex_str.trim()).context("decode ecdsa sig")?;
    Signature::from_compact(&bytes).map_err(|e| anyhow!("ecdsa sig: {e}"))
}

fn range_payouts(package: &SignPackage) -> Vec<RangePayout> {
    package.range_payouts.iter().map(RangePayout::from).collect()
}

fn cets(package: &SignPackage) -> Result<Vec<Transaction>> {
    package.cets.iter().map(|h| tx_from_hex(h)).collect()
}

fn rebuild_trie(package: &SignPackage) -> Result<MultiOracleTrie> {
    let oni = OracleNumericInfo {
        base: package.base,
        nb_digits: vec![package.nb_digits],
    };
    let mut trie = MultiOracleTrie::new(&oni, 1).map_err(|e| anyhow!("trie new: {:?}", e))?;
    let payouts = range_payouts(package);
    trie.generate(0, &payouts)
        .map_err(|e| anyhow!("trie generate: {:?}", e))?;
    Ok(trie)
}

pub fn sign_adaptor(
    secp: &Secp256k1<All>,
    seckey: &SecretKey,
    package: &SignPackage,
) -> Result<PartySignatures> {
    let ann = parse_announcement(&package.oracle_announcement)?;
    let (base, nb_digits) = announcement_digits(&ann)?;
    if base != package.base || nb_digits != package.nb_digits {
        bail!("announcement digits do not match sign package");
    }
    let oni = OracleNumericInfo {
        base,
        nb_digits: vec![nb_digits],
    };
    let mut trie = MultiOracleTrie::new(&oni, 1).map_err(|e| anyhow!("trie new: {:?}", e))?;
    let payouts = range_payouts(package);
    let cets = cets(package)?;
    let precomputed = precompute_points(secp, &ann)?;
    let funding_script = script_from_hex(&package.funding_script_hex)?;
    let fund_value = Amount::from_sat(package.fund_value_sats);
    let adaptor_sigs = trie
        .generate_sign(
            secp,
            seckey,
            &funding_script,
            fund_value,
            &payouts,
            &cets,
            &precomputed,
            0,
        )
        .map_err(|e| anyhow!("generate_sign: {:?}", e))?;

    let refund = tx_from_hex(&package.refund_tx_hex)?;
    let refund_sig = dlc::util::get_raw_sig_for_tx_input(
        secp,
        &refund,
        0,
        &funding_script,
        fund_value,
        seckey,
    )
    .map_err(|e| anyhow!("refund sig: {:?}", e))?;

    Ok(PartySignatures {
        adaptor_sigs: adaptor_sigs.iter().map(adaptor_to_hex).collect(),
        refund_sig: ecdsa_to_hex(&refund_sig),
    })
}

fn signatures_to_secret(signatures: &[Vec<SchnorrSig>]) -> Result<SecretKey> {
    let s_values = signatures
        .iter()
        .flatten()
        .map(|x| {
            dlc::secp_utils::schnorrsig_decompose(x)
                .map(|v| v.1)
                .map_err(|e| anyhow!("decompose: {:?}", e))
        })
        .collect::<Result<Vec<&[u8]>>>()?;
    if s_values.is_empty() {
        bail!("no oracle signature s-values");
    }
    let secret = SecretKey::from_slice(s_values[0]).map_err(|e| anyhow!("s-value: {e}"))?;
    let result = s_values.iter().skip(1).fold(secret, |accum, s| {
        let sec = SecretKey::from_slice(s).expect("oracle s-value");
        accum.add_tweak(&Scalar::from(sec)).expect("tweak s-values")
    });
    Ok(result)
}

fn finalize_sig(sig: &Signature) -> Vec<u8> {
    [
        sig.serialize_der().as_ref(),
        &[EcdsaSighashType::All.to_u32() as u8],
    ]
    .concat()
}

fn assemble_multisig_witness(
    first_sig: &Signature,
    first_pk: &PublicKey,
    second_sig: &Signature,
    second_pk: &PublicKey,
    funding_script: &ScriptBuf,
) -> Witness {
    let a = finalize_sig(first_sig);
    let b = finalize_sig(second_sig);
    if first_pk < second_pk {
        Witness::from_slice(&[Vec::new(), a, b, funding_script.to_bytes()])
    } else {
        Witness::from_slice(&[Vec::new(), b, a, funding_script.to_bytes()])
    }
}

pub fn parse_attestation_digits(att: &Value) -> Result<(Vec<SchnorrSig>, Vec<usize>)> {
    let sigs_v = att["signatures"]
        .as_array()
        .ok_or_else(|| anyhow!("attestation.signatures"))?;
    let mut sigs = Vec::with_capacity(sigs_v.len());
    for s in sigs_v {
        let h = s.as_str().ok_or_else(|| anyhow!("signature not string"))?;
        let bytes = hex::decode(h).context("decode signature hex")?;
        sigs.push(SchnorrSig::from_slice(&bytes).context("parse schnorr signature")?);
    }
    let vals = att["values"]
        .as_array()
        .or_else(|| att["outcomes"].as_array())
        .ok_or_else(|| anyhow!("attestation.values/outcomes"))?;
    let mut digits = Vec::with_capacity(vals.len());
    for v in vals {
        let d = match v {
            Value::String(s) => s.parse::<usize>().context("parse digit")?,
            Value::Number(n) => n.as_u64().ok_or_else(|| anyhow!("digit num"))? as usize,
            _ => bail!("bad digit value"),
        };
        digits.push(d);
    }
    Ok((sigs, digits))
}

/// Complete the attested CET using **both** parties' adaptor signatures.
/// No private key required — the oracle attestation decrypts the adaptor sigs.
pub fn complete_cet(
    package: &SignPackage,
    offerer_adaptor_sigs: &[String],
    acceptor_adaptor_sigs: &[String],
    attestation: &Value,
) -> Result<(Transaction, i64, u64, u64)> {
    let (sigs, digits) = parse_attestation_digits(attestation)?;
    let trie = rebuild_trie(package)?;
    let (range_info, paths) = trie
        .look_up(&[(0usize, digits.clone())])
        .ok_or_else(|| anyhow!("no CET matches attested outcome"))?;
    let prefix_len = paths[0].1.len();
    let oracle_sigs: Vec<Vec<SchnorrSig>> = vec![sigs[..prefix_len].to_vec()];
    let adaptor_secret = signatures_to_secret(&oracle_sigs)?;

    let offerer_adaptor = adaptor_from_hex(
        offerer_adaptor_sigs
            .get(range_info.adaptor_index)
            .ok_or_else(|| anyhow!("missing offerer adaptor sig"))?,
    )?;
    let acceptor_adaptor = adaptor_from_hex(
        acceptor_adaptor_sigs
            .get(range_info.adaptor_index)
            .ok_or_else(|| anyhow!("missing acceptor adaptor sig"))?,
    )?;
    let offerer_sig = offerer_adaptor
        .decrypt(&adaptor_secret)
        .map_err(|e| anyhow!("decrypt offerer adaptor: {e}"))?;
    let acceptor_sig = acceptor_adaptor
        .decrypt(&adaptor_secret)
        .map_err(|e| anyhow!("decrypt acceptor adaptor: {e}"))?;

    let mut cet = tx_from_hex(
        package
            .cets
            .get(range_info.cet_index)
            .ok_or_else(|| anyhow!("missing CET"))?,
    )?;
    let offerer_pk = parse_pk(&package.peg_fund_pubkey)?;
    let acceptor_pk = parse_pk(&package.investor_fund_pubkey)?;
    let funding_script = script_from_hex(&package.funding_script_hex)?;
    cet.input[0].witness = assemble_multisig_witness(
        &offerer_sig,
        &offerer_pk,
        &acceptor_sig,
        &acceptor_pk,
        &funding_script,
    );

    let peg_spk = payout_spk(&package.peg_payout_address)?;
    let inv_spk = payout_spk(&package.investor_payout_address)?;
    let peg_sats = cet
        .output
        .iter()
        .find(|o| o.script_pubkey == peg_spk)
        .map(|o| o.value.to_sat())
        .unwrap_or(0);
    let investor_sats = cet
        .output
        .iter()
        .find(|o| o.script_pubkey == inv_spk)
        .map(|o| o.value.to_sat())
        .unwrap_or(0);
    let outcome = crate::curve::digits_to_int(&digits, package.base);
    Ok((cet, outcome, peg_sats, investor_sats))
}

pub fn complete_refund(
    package: &SignPackage,
    offerer_refund_sig: &str,
    acceptor_refund_sig: &str,
) -> Result<Transaction> {
    let mut refund = tx_from_hex(&package.refund_tx_hex)?;
    let offerer_sig = ecdsa_from_hex(offerer_refund_sig)?;
    let acceptor_sig = ecdsa_from_hex(acceptor_refund_sig)?;
    let offerer_pk = parse_pk(&package.peg_fund_pubkey)?;
    let acceptor_pk = parse_pk(&package.investor_fund_pubkey)?;
    let funding_script = script_from_hex(&package.funding_script_hex)?;
    refund.input[0].witness = assemble_multisig_witness(
        &offerer_sig,
        &offerer_pk,
        &acceptor_sig,
        &acceptor_pk,
        &funding_script,
    );
    Ok(refund)
}

pub fn parse_address(s: &str, network: bitcoin::Network) -> Result<ScriptBuf> {
    Ok(bitcoin::Address::from_str(s)
        .with_context(|| format!("parse address {s}"))?
        .require_network(network)
        .with_context(|| format!("address {s} not {network}"))?
        .script_pubkey())
}

fn payout_spk(addr: &str) -> Result<ScriptBuf> {
    let parsed = bitcoin::Address::from_str(addr).with_context(|| format!("parse address {addr}"))?;
    Ok(parsed.assume_checked().script_pubkey())
}

pub fn random_serial() -> u64 {
    thread_rng().gen()
}

pub fn serialize_tx(tx: &Transaction) -> String {
    serialize_hex(tx)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pubkey_round_trip() {
        let secp = Secp256k1::new();
        let sk = SecretKey::from_slice(&[0x11u8; 32]).unwrap();
        let pk = PublicKey::from_secret_key(&secp, &sk);
        let hex = hex_pk(&pk);
        assert_eq!(parse_pk(&hex).unwrap(), pk);
    }

    #[test]
    fn attestation_digits_parse_numeric_outcomes() {
        let att = serde_json::json!({
            "signatures": [],
            "outcomes": [1, 0, 1]
        });
        let (sigs, digits) = parse_attestation_digits(&att).unwrap();
        assert!(sigs.is_empty());
        assert_eq!(digits, vec![1, 0, 1]);
    }
}
