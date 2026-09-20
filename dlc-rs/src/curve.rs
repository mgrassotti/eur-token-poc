//! FloorEUR payout curve → rust-dlc RangePayouts, plus oracle adaptor points.

use anyhow::{anyhow, bail, Context, Result};
use bitcoin::hashes::{sha256, Hash};
use bitcoin::Amount;
use dlc::{Payout, RangePayout};
use dlc_messages::oracle_msgs::{EventDescriptor, OracleAnnouncement};
use dlc_trie::digit_decomposition::pad_range_payouts;
use secp256k1_zkp::{All, Message, PublicKey, Secp256k1};

pub fn peg_payout_at(points: &[(i64, i64)], outcome: i64, total: i64) -> i64 {
    if points.is_empty() {
        return total;
    }
    let mut sorted = points.to_vec();
    sorted.sort_by_key(|p| p.0);
    if outcome <= sorted[0].0 {
        return sorted[0].1.min(total).max(0);
    }
    let last = *sorted.last().unwrap();
    if outcome >= last.0 {
        return last.1.max(0).min(total);
    }
    for w in sorted.windows(2) {
        let (a, b) = (w[0], w[1]);
        if outcome >= a.0 && outcome <= b.0 {
            let span = (b.0 - a.0).max(1) as f64;
            let t = (outcome - a.0) as f64 / span;
            let v = a.1 as f64 + t * (b.1 - a.1) as f64;
            return (v.round() as i64).clamp(0, total);
        }
    }
    last.1
}

pub fn build_range_payouts(
    points: &[(i64, i64)],
    total: u64,
    base: usize,
    nb_digits: usize,
    rounding_buckets: u64,
) -> Vec<RangePayout> {
    let max_value: usize = base.pow(nb_digits as u32);
    let rounding_mod = (total / rounding_buckets).max(1) as i64;
    let total_i = total as i64;

    let round_peg = |outcome: i64| -> u64 {
        let raw = peg_payout_at(points, outcome, total_i);
        let r = ((raw + rounding_mod / 2) / rounding_mod) * rounding_mod;
        r.clamp(0, total_i) as u64
    };

    let mut ranges: Vec<RangePayout> = Vec::new();
    let mut start = 0usize;
    let mut cur_peg = round_peg(0);
    for outcome in 1..max_value {
        let peg = round_peg(outcome as i64);
        if peg != cur_peg {
            ranges.push(RangePayout {
                start,
                count: outcome - start,
                payout: Payout {
                    offer: Amount::from_sat(cur_peg),
                    accept: Amount::from_sat(total - cur_peg),
                },
            });
            start = outcome;
            cur_peg = peg;
        }
    }
    ranges.push(RangePayout {
        start,
        count: max_value - start,
        payout: Payout {
            offer: Amount::from_sat(cur_peg),
            accept: Amount::from_sat(total - cur_peg),
        },
    });

    pad_range_payouts(ranges, base, nb_digits)
}

pub fn precompute_points(
    secp: &Secp256k1<All>,
    ann: &OracleAnnouncement,
) -> Result<Vec<Vec<Vec<PublicKey>>>> {
    let pubkey = ann.oracle_public_key;
    let nonces = &ann.oracle_event.oracle_nonces;
    let (base, nb_digits) = match &ann.oracle_event.event_descriptor {
        EventDescriptor::DigitDecompositionEvent(d) => (d.base as usize, d.nb_digits as usize),
        _ => bail!("expected digit decomposition event"),
    };
    if nb_digits != nonces.len() {
        bail!("nb_digits ({}) != nonces ({})", nb_digits, nonces.len());
    }
    let mut d_points = Vec::with_capacity(nb_digits);
    for nonce in nonces {
        let mut points = Vec::with_capacity(base);
        for j in 0..base {
            let hash = sha256::Hash::hash(j.to_string().as_bytes()).to_byte_array();
            let msg = Message::from_digest(hash);
            points.push(dlc::secp_utils::schnorrsig_compute_sig_point(
                secp, &pubkey, nonce, &msg,
            ).map_err(|e| anyhow!("sig point: {:?}", e))?);
        }
        d_points.push(points);
    }
    Ok(vec![d_points])
}

pub fn announcement_digits(ann: &OracleAnnouncement) -> Result<(usize, usize)> {
    match &ann.oracle_event.event_descriptor {
        EventDescriptor::DigitDecompositionEvent(d) => Ok((d.base as usize, d.nb_digits as usize)),
        _ => Err(anyhow!("announcement is not a digit decomposition event")),
    }
}

pub fn parse_announcement(raw: &str) -> Result<OracleAnnouncement> {
    serde_json::from_str(raw).context("parse oracle_announcement")
}

pub fn digits_to_int(digits: &[usize], base: usize) -> i64 {
    digits
        .iter()
        .fold(0i64, |acc, d| acc * base as i64 + *d as i64)
}
