//! Rust DLC node (rust-dlc) REST sidecar for the FloorEUR PoC on regtest.
//!
//! Drop-in replacement for the node-dlc/cfd-dlc-js shim: it speaks the exact same
//! HTTP contract the Ruby `Dlc::NodeClient` already uses, but the on-chain DLC
//! engine is **rust-dlc** (`dlc` + `dlc-trie`), pinned to the *same commit* the
//! Pythia oracle is built from. Because the oracle (Pythia) and this node share
//! the identical rust-dlc + secp256k1-zkp code, the ECDSA-adaptor signature point
//! and the oracle s-value decomposition agree byte-for-byte — which is precisely
//! the compatibility that the cfd-dlc-js engine lacked (NULLFAIL on EXECUTE).
//!
//! PoC scope: this process owns BOTH parties' keys (peg = offerer, investor =
//! acceptor) and drives the full offer/accept/sign handshake in-process, funding
//! the 2-of-2 from a bitcoind regtest wallet.
//!
//! Endpoint contract (matches Dlc::NodeClient):
//!   GET  /info                       -> { pubkey, network }
//!   POST /contracts                  -> { contract_id, funding_txid, funding_vout, funding_address, status }
//!   GET  /contracts/:id              -> { contract_id, status, funding_txid, funding_vout }
//!   POST /contracts/:id/execute      -> { cet_txid, outcome, peg_sats, investor_sats }
//!   POST /contracts/:id/refund       -> { refund_txid }
//!   POST /contracts/:id/distribute   -> { txid, payouts }

use std::collections::HashMap;
use std::str::FromStr;

use anyhow::{anyhow, bail, Context, Result};
use bitcoin::absolute::LockTime;
use bitcoin::hashes::{sha256, Hash};
use bitcoin::sighash::EcdsaSighashType;
use bitcoin::transaction::Version;
use bitcoin::{
    Amount, KnownHrp, Network, OutPoint, ScriptBuf, Sequence, Transaction, TxIn, TxOut, Txid,
    Witness,
};

use dlc::{create_dlc_transactions, DlcTransactions, Payout, PartyParams, TxInputInfo};
use dlc_messages::oracle_msgs::{EventDescriptor, OracleAnnouncement};
use dlc_trie::digit_decomposition::pad_range_payouts;
use dlc_trie::multi_oracle_trie::MultiOracleTrie;
use dlc_trie::{DlcTrie, OracleNumericInfo};

use secp256k1_zkp::rand::{thread_rng, Rng};
use secp256k1_zkp::{
    schnorr::Signature as SchnorrSig, All, EcdsaAdaptorSignature, Message, PublicKey, Secp256k1,
    SecretKey,
};

use serde_json::{json, Value};
use tiny_http::{Method, Response, Server};

const MAX_WITNESS_LEN: usize = 107; // P2WPKH low-R

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
struct Config {
    port: u16,
    rpc_url: String,
    rpc_user: String,
    rpc_pass: String,
    miner_wallet: String,
    watch_wallet: String,
    peg_sk: SecretKey,
    investor_sk: SecretKey,
    rounding_buckets: u64,
}

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

fn sk_from_env(key: &str, default_hex: &str) -> SecretKey {
    let h = env_or(key, default_hex);
    let bytes = hex::decode(h).expect("invalid secret key hex");
    SecretKey::from_slice(&bytes).expect("invalid secret key")
}

impl Config {
    fn load() -> Self {
        Config {
            port: env_or("PORT", "8090").parse().unwrap_or(8090),
            rpc_url: env_or("BITCOIND_RPC_URL", "http://127.0.0.1:18443"),
            rpc_user: env_or("BITCOIND_RPC_USER", "regtest"),
            rpc_pass: env_or("BITCOIND_RPC_PASSWORD", "regtest"),
            miner_wallet: env_or("MINER_WALLET", "miner"),
            watch_wallet: env_or("WATCH_WALLET", "dlcwatch"),
            // Deterministic regtest keys (NOT for any real funds).
            peg_sk: sk_from_env(
                "PEG_SECKEY",
                "1111111111111111111111111111111111111111111111111111111111111111",
            ),
            investor_sk: sk_from_env(
                "INVESTOR_SECKEY",
                "2222222222222222222222222222222222222222222222222222222222222222",
            ),
            rounding_buckets: env_or("DLC_ROUNDING_BUCKETS", "20").parse().unwrap_or(20),
        }
    }
}

// ---------------------------------------------------------------------------
// bitcoind JSON-RPC (ureq)
// ---------------------------------------------------------------------------
struct Rpc {
    url: String,
    auth: String,
}

impl Rpc {
    fn new(cfg: &Config) -> Self {
        let auth = format!(
            "Basic {}",
            base64(format!("{}:{}", cfg.rpc_user, cfg.rpc_pass).as_bytes())
        );
        Rpc {
            url: cfg.rpc_url.trim_end_matches('/').to_string(),
            auth,
        }
    }

    fn call(&self, method: &str, params: Value, wallet: Option<&str>) -> Result<Value> {
        let path = match wallet {
            Some(w) => format!("{}/wallet/{}", self.url, w),
            None => self.url.clone(),
        };
        let body = json!({ "jsonrpc": "1.0", "id": "dlc", "method": method, "params": params });
        let resp = ureq::post(&path)
            .set("Authorization", &self.auth)
            .set("Content-Type", "text/plain")
            .send_string(&body.to_string());

        let text = match resp {
            Ok(r) => r.into_string()?,
            Err(ureq::Error::Status(_, r)) => r.into_string()?,
            Err(e) => return Err(anyhow!("rpc transport {}: {}", method, e)),
        };
        let v: Value = serde_json::from_str(&text)
            .with_context(|| format!("{}: {}", method, &text[..text.len().min(200)]))?;
        if !v["error"].is_null() {
            bail!("{}: {}", method, v["error"]);
        }
        Ok(v["result"].clone())
    }

    fn try_call(&self, method: &str, params: Value, wallet: Option<&str>) {
        let _ = self.call(method, params, wallet);
    }
}

// Minimal base64 (no external dep) for the RPC Basic auth header.
fn base64(input: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in input.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | (b[2] as u32);
        out.push(T[((n >> 18) & 63) as usize] as char);
        out.push(T[((n >> 12) & 63) as usize] as char);
        out.push(if chunk.len() > 1 {
            T[((n >> 6) & 63) as usize] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            T[(n & 63) as usize] as char
        } else {
            '='
        });
    }
    out
}

// ---------------------------------------------------------------------------
// Wallet: a single deterministic key per party, used both as the funding-input
// key (P2WPKH) and as the 2-of-2 fund/payout/change key. Adequate for the PoC.
// ---------------------------------------------------------------------------
struct Party {
    sk: SecretKey,
    pk: PublicKey,
    spk: ScriptBuf,
    address: String,
}

impl Party {
    fn new(secp: &Secp256k1<All>, sk: SecretKey) -> Self {
        let pk = PublicKey::from_secret_key(secp, &sk);
        let cpk = bitcoin::CompressedPublicKey(pk);
        let spk = ScriptBuf::new_p2wpkh(&cpk.wpubkey_hash());
        let address = bitcoin::Address::p2wpkh(&cpk, KnownHrp::Regtest).to_string();
        Party {
            sk,
            pk,
            spk,
            address,
        }
    }
}

// ---------------------------------------------------------------------------
// Chain helpers
// ---------------------------------------------------------------------------
struct Chain<'a> {
    rpc: &'a Rpc,
    miner: String,
    watch: String,
}

impl<'a> Chain<'a> {
    fn ensure(&self) -> Result<()> {
        self.rpc.try_call("createwallet", json!([self.miner]), None);
        self.rpc.try_call("loadwallet", json!([self.miner]), None);
        // descriptors watch-only: disable_privkeys=true, blank=true, ..., descriptors=true
        self.rpc.try_call(
            "createwallet",
            json!([self.watch, true, true, "", false, true]),
            None,
        );
        self.rpc.try_call("loadwallet", json!([self.watch]), None);

        let balance = self
            .rpc
            .call("getbalance", json!([]), Some(&self.miner))
            .ok()
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        if balance < 50.0 {
            let addr = self.miner_address()?;
            self.rpc
                .call("generatetoaddress", json!([101, addr]), None)?;
        }
        Ok(())
    }

    fn miner_address(&self) -> Result<String> {
        Ok(self
            .rpc
            .call("getnewaddress", json!([]), Some(&self.miner))?
            .as_str()
            .ok_or_else(|| anyhow!("getnewaddress"))?
            .to_string())
    }

    fn mine(&self, n: u64) -> Result<()> {
        let addr = self.miner_address()?;
        self.rpc
            .call("generatetoaddress", json!([n, addr]), None)?;
        Ok(())
    }

    fn block_count(&self) -> Result<u64> {
        Ok(self
            .rpc
            .call("getblockcount", json!([]), None)?
            .as_u64()
            .ok_or_else(|| anyhow!("getblockcount"))?)
    }

    fn broadcast(&self, tx: &Transaction) -> Result<String> {
        let hex = bitcoin::consensus::encode::serialize_hex(tx);
        let txid = self
            .rpc
            .call("sendrawtransaction", json!([hex]), None)?
            .as_str()
            .ok_or_else(|| anyhow!("sendrawtransaction"))?
            .to_string();
        self.mine(1)?;
        Ok(txid)
    }
}

// ---------------------------------------------------------------------------
// Payout curve -> RangePayouts (FloorEUR peg = K/price hyperbola, sampled +
// rounded so that consecutive equal-payout outcomes coalesce into one CET).
// ---------------------------------------------------------------------------
fn peg_payout_at(points: &[(i64, i64)], outcome: i64, total: i64) -> i64 {
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

fn build_range_payouts(
    points: &[(i64, i64)],
    total: u64,
    base: usize,
    nb_digits: usize,
    rounding_buckets: u64,
) -> Vec<dlc::RangePayout> {
    let max_value: usize = base.pow(nb_digits as u32);
    let rounding_mod = (total / rounding_buckets).max(1) as i64;
    let total_i = total as i64;

    let round_peg = |outcome: i64| -> u64 {
        let raw = peg_payout_at(points, outcome, total_i);
        let r = ((raw + rounding_mod / 2) / rounding_mod) * rounding_mod;
        r.clamp(0, total_i) as u64
    };

    let mut ranges: Vec<dlc::RangePayout> = Vec::new();
    let mut start = 0usize;
    let mut cur_peg = round_peg(0);
    for outcome in 1..max_value {
        let peg = round_peg(outcome as i64);
        if peg != cur_peg {
            ranges.push(dlc::RangePayout {
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
    ranges.push(dlc::RangePayout {
        start,
        count: max_value - start,
        payout: Payout {
            offer: Amount::from_sat(cur_peg),
            accept: Amount::from_sat(total - cur_peg),
        },
    });

    pad_range_payouts(ranges, base, nb_digits)
}

// Per-digit signature points: identical encoding to rust-dlc/Pythia
// (msg = sha256(digit_string), schnorrsig_compute_sig_point).
fn precompute_points(
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
            )?);
        }
        d_points.push(points);
    }
    Ok(vec![d_points])
}

fn digits_to_int(digits: &[usize], base: usize) -> i64 {
    digits.iter().fold(0i64, |acc, d| acc * base as i64 + *d as i64)
}

// ---------------------------------------------------------------------------
// In-memory contract store
// ---------------------------------------------------------------------------
struct Contract {
    dlc_txs: DlcTransactions,
    trie: MultiOracleTrie,
    adaptor_sigs: Vec<EcdsaAdaptorSignature>,
    funding_script: ScriptBuf,
    fund_value: Amount,
    base: usize,
    points: Vec<(i64, i64)>,
    total: i64,
    funding_txid: String,
    refund_lock_time: u32,
    status: String,
    // Recorded at execute: the peg-side CET output (P2WPKH, sidecar peg key)
    // that `distribute` later spends to fan the peg_pot out to the holders.
    peg_payout_outpoint: Option<OutPoint>,
    peg_payout_value: Option<u64>,
}

struct App {
    cfg: Config,
    secp: Secp256k1<All>,
    peg: Party,
    investor: Party,
    contracts: HashMap<String, Contract>,
    seq: u64,
}

impl App {
    fn rpc(&self) -> Rpc {
        Rpc::new(&self.cfg)
    }
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------
fn handle_info(app: &App) -> Result<Value> {
    Ok(json!({
        "pubkey": app.peg.pk.to_string(),
        "network": "regtest",
    }))
}

fn parse_points(v: &Value) -> Vec<(i64, i64)> {
    v.as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(|p| {
                    let o = p["outcome"].as_i64()?;
                    let peg = p["peg_sats"].as_i64()?;
                    Some((o, peg))
                })
                .collect()
        })
        .unwrap_or_default()
}

fn parse_inputs(v: &Value) -> Result<Vec<(OutPoint, u64)>> {
    let arr = v.as_array().ok_or_else(|| anyhow!("inputs must be an array"))?;
    let mut out = Vec::with_capacity(arr.len());
    for it in arr {
        let txid = Txid::from_str(it["txid"].as_str().ok_or_else(|| anyhow!("input.txid"))?)?;
        let vout = it["vout"].as_u64().ok_or_else(|| anyhow!("input.vout"))? as u32;
        let amount = it["amount_sats"]
            .as_u64()
            .ok_or_else(|| anyhow!("input.amount_sats"))?;
        out.push((OutPoint { txid, vout }, amount));
    }
    Ok(out)
}

fn parse_address(s: &str) -> Result<ScriptBuf> {
    Ok(bitcoin::Address::from_str(s)
        .with_context(|| format!("parse address {}", s))?
        .require_network(Network::Regtest)
        .with_context(|| format!("address {} not regtest", s))?
        .script_pubkey())
}

fn party_inputs(inputs: &[(OutPoint, u64)]) -> (Vec<TxInputInfo>, u64) {
    let infos = inputs
        .iter()
        .map(|(op, _)| TxInputInfo {
            outpoint: *op,
            max_witness_len: MAX_WITNESS_LEN,
            redeem_script: ScriptBuf::new(),
            serial_id: thread_rng().gen(),
        })
        .collect();
    let amount = inputs.iter().map(|(_, a)| *a).sum();
    (infos, amount)
}

// Fase 1: the DLC 2-of-2 funding tx is funded from the users' real L1 reserve
// UTXOs (provided by Ruby), not from the sidecar miner wallet. We build the
// unsigned funding tx + CET set + adaptor sigs here; Ruby signs the P2WPKH
// funding inputs with the reserve wallets and broadcasts the SAME tx (segwit
// txid is stable, so the CETs stay valid). The 2-of-2 FUND keys remain the
// sidecar's (app.peg/app.investor), so adaptor sigs / sign_cet / refund are
// unchanged. Only the funding inputs and the CET payout/change scriptpubkeys
// point at real reserve addresses.
fn handle_create(app: &mut App, body: &Value) -> Result<Value> {
    let rpc = app.rpc();
    let chain = Chain {
        rpc: &rpc,
        miner: app.cfg.miner_wallet.clone(),
        watch: app.cfg.watch_wallet.clone(),
    };
    // Wallets may be gone after a regtest chain reset; (re)create the miner/watch
    // wallets so later mining (execute/distribute/refund) works. This no longer
    // funds the DLC parties — the collateral comes from the reserve UTXOs.
    chain.ensure().context("ensure chain")?;

    let ann_str = match &body["oracle_announcement"] {
        Value::String(s) => s.clone(),
        v => v.to_string(),
    };
    let ann: OracleAnnouncement =
        serde_json::from_str(&ann_str).context("parse oracle_announcement")?;

    let (base, nb_digits) = match &ann.oracle_event.event_descriptor {
        EventDescriptor::DigitDecompositionEvent(d) => (d.base as usize, d.nb_digits as usize),
        _ => bail!("announcement is not a digit decomposition event"),
    };

    let offer = body["offer_collateral_sats"]
        .as_u64()
        .ok_or_else(|| anyhow!("offer_collateral_sats"))?;
    let accept = body["accept_collateral_sats"]
        .as_u64()
        .ok_or_else(|| anyhow!("accept_collateral_sats"))?;
    let total = offer + accept;
    let fee_rate = body["fee_rate_sats_vb"].as_u64().unwrap_or(5);
    let points = parse_points(&body["payouts"]);

    let peg_inputs = parse_inputs(&body["peg_inputs"]).context("peg_inputs")?;
    let investor_inputs = parse_inputs(&body["investor_inputs"]).context("investor_inputs")?;
    if peg_inputs.is_empty() || investor_inputs.is_empty() {
        bail!("peg_inputs and investor_inputs are required and must be non-empty");
    }
    let peg_change_spk = parse_address(
        body["peg_change_address"]
            .as_str()
            .ok_or_else(|| anyhow!("peg_change_address"))?,
    )?;
    let investor_change_spk = parse_address(
        body["investor_change_address"]
            .as_str()
            .ok_or_else(|| anyhow!("investor_change_address"))?,
    )?;
    let investor_payout_spk = parse_address(
        body["investor_payout_address"]
            .as_str()
            .ok_or_else(|| anyhow!("investor_payout_address"))?,
    )?;

    let (peg_input_infos, peg_input_amount) = party_inputs(&peg_inputs);
    let (investor_input_infos, investor_input_amount) = party_inputs(&investor_inputs);

    let height = chain.block_count()? as u32;
    let cet_lock_time = height;
    let req_refund = body["refund_locktime"].as_u64().unwrap_or(0) as u32;
    let refund_lock_time = req_refund.max(height + 2);

    let offer_params = PartyParams {
        fund_pubkey: app.peg.pk,
        change_script_pubkey: peg_change_spk,
        change_serial_id: thread_rng().gen(),
        // Peg payout stays the sidecar peg address; `distribute` fans it out to
        // the individual holders' reserve addresses at settlement.
        payout_script_pubkey: app.peg.spk.clone(),
        payout_serial_id: thread_rng().gen(),
        inputs: peg_input_infos,
        input_amount: Amount::from_sat(peg_input_amount),
        collateral: Amount::from_sat(offer),
    };
    let accept_params = PartyParams {
        fund_pubkey: app.investor.pk,
        change_script_pubkey: investor_change_spk,
        // Investor collateral returns straight to the investor's L1 reserve.
        payout_script_pubkey: investor_payout_spk,
        payout_serial_id: thread_rng().gen(),
        change_serial_id: thread_rng().gen(),
        inputs: investor_input_infos,
        input_amount: Amount::from_sat(investor_input_amount),
        collateral: Amount::from_sat(accept),
    };

    eprintln!("[dlc-node] create: build range payouts");
    let range_payouts =
        build_range_payouts(&points, total, base, nb_digits, app.cfg.rounding_buckets);
    let payouts: Vec<Payout> = range_payouts.iter().map(|r| r.payout.clone()).collect();

    eprintln!(
        "[dlc-node] create: {} CETs, create_dlc_transactions",
        payouts.len()
    );
    let dlc_txs = create_dlc_transactions(
        &offer_params,
        &accept_params,
        &payouts,
        refund_lock_time,
        fee_rate,
        0,
        cet_lock_time,
        thread_rng().gen(),
    )
    .map_err(|e| anyhow!("create_dlc_transactions: {:?}", e))?;

    let funding_script = dlc_txs.funding_script_pubkey.clone();
    let fund_value = dlc_txs.get_fund_output().value;

    eprintln!("[dlc-node] create: generate accept-side adaptor sigs");
    let oni = OracleNumericInfo {
        base,
        nb_digits: vec![nb_digits],
    };
    let mut trie = MultiOracleTrie::new(&oni, 1).map_err(|e| anyhow!("trie new: {:?}", e))?;
    let precomputed = precompute_points(&app.secp, &ann)?;
    let adaptor_sigs = trie
        .generate_sign(
            &app.secp,
            &app.investor.sk,
            &funding_script,
            fund_value,
            &range_payouts,
            &dlc_txs.cets,
            &precomputed,
            0,
        )
        .map_err(|e| anyhow!("generate_sign: {:?}", e))?;

    // Do NOT sign or broadcast: Ruby signs the P2WPKH funding inputs with the
    // reserve wallets and broadcasts. The segwit txid is stable pre-witness, so
    // the CETs (which reference this outpoint) remain valid.
    let funding_txid = dlc_txs.fund.compute_txid().to_string();
    let funding_tx_hex = bitcoin::consensus::encode::serialize_hex(&dlc_txs.fund);
    let fund_vout = dlc_txs.get_fund_output_index() as u64;
    eprintln!(
        "[dlc-node] create: unsigned funding {} (vout {}), awaiting reserve signing",
        funding_txid, fund_vout
    );

    let id = body["contract_id"]
        .as_str()
        .map(|s| s.to_string())
        .unwrap_or_else(|| {
            app.seq += 1;
            format!("dlc-{}", app.seq)
        });

    app.contracts.insert(
        id.clone(),
        Contract {
            dlc_txs,
            trie,
            adaptor_sigs,
            funding_script,
            fund_value,
            base,
            points,
            total: total as i64,
            funding_txid: funding_txid.clone(),
            refund_lock_time,
            status: "pending_funding".to_string(),
            peg_payout_outpoint: None,
            peg_payout_value: None,
        },
    );

    Ok(json!({
        "contract_id": id,
        "funding_txid": funding_txid,
        "funding_vout": fund_vout,
        "funding_tx_hex": funding_tx_hex,
        "status": "pending_funding",
    }))
}

fn handle_get(app: &App, id: &str) -> Result<Value> {
    let c = app
        .contracts
        .get(id)
        .ok_or_else(|| anyhow!("unknown contract"))?;
    Ok(json!({
        "contract_id": id,
        "status": c.status,
        "funding_txid": c.funding_txid,
        "funding_vout": c.dlc_txs.get_fund_output_index() as u64,
    }))
}

fn parse_attestation(att: &Value) -> Result<(Vec<SchnorrSig>, Vec<usize>)> {
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

fn handle_execute(app: &mut App, id: &str, body: &Value) -> Result<Value> {
    let rpc = app.rpc();
    let chain = Chain {
        rpc: &rpc,
        miner: app.cfg.miner_wallet.clone(),
        watch: app.cfg.watch_wallet.clone(),
    };

    let att_val = match &body["attestation"] {
        Value::String(s) => serde_json::from_str::<Value>(s).context("parse attestation json")?,
        v => v.clone(),
    };
    let (sigs, digits) = parse_attestation(&att_val)?;

    let c = app
        .contracts
        .get_mut(id)
        .ok_or_else(|| anyhow!("unknown contract"))?;

    // Locate the CET + adaptor signature for the attested outcome.
    let (range_info, paths) = c
        .trie
        .look_up(&[(0usize, digits.clone())])
        .ok_or_else(|| anyhow!("no CET matches attested outcome"))?;
    let prefix_len = paths[0].1.len();
    let oracle_sigs: Vec<Vec<SchnorrSig>> = vec![sigs[..prefix_len].to_vec()];

    let mut cet = c.dlc_txs.cets[range_info.cet_index].clone();
    let adaptor = c.adaptor_sigs[range_info.adaptor_index];

    // Decrypt the investor (accept-side) adaptor signature with the oracle
    // attestation and co-sign with the peg fund key. With matching rust-dlc this
    // produces a valid 2-of-2 witness (no more NULLFAIL).
    dlc::sign_cet(
        &app.secp,
        &mut cet,
        &adaptor,
        &oracle_sigs,
        &app.peg.sk,
        &app.investor.pk,
        &c.funding_script,
        c.fund_value,
    )
    .map_err(|e| anyhow!("sign_cet: {:?}", e))?;

    let cet_txid = chain.broadcast(&cet)?;

    let outcome = digits_to_int(&digits, c.base);

    // Record the peg-side CET output (the one paying the sidecar peg address) so
    // `distribute` can later spend it to fan the peg_pot out to the holders. We
    // report the ACTUAL on-chain output values (bucketed by the CET set), which
    // is what `distribute` can actually spend — not the raw curve value.
    let cet_txid_parsed = Txid::from_str(&cet_txid)?;
    let peg_output = cet
        .output
        .iter()
        .enumerate()
        .find(|(_, o)| o.script_pubkey == app.peg.spk);
    let (peg_sats, investor_sats) = match peg_output {
        Some((idx, txout)) => {
            let value = txout.value.to_sat();
            c.peg_payout_outpoint = Some(OutPoint {
                txid: cet_txid_parsed,
                vout: idx as u32,
            });
            c.peg_payout_value = Some(value);
            (value as i64, c.total - value as i64)
        }
        // Peg output dust-discarded (peg received nothing): investor took it all.
        None => (0, c.total),
    };

    c.status = "executed".to_string();

    Ok(json!({
        "cet_txid": cet_txid,
        "outcome": outcome,
        "peg_sats": peg_sats,
        "investor_sats": investor_sats,
    }))
}

fn handle_refund(app: &mut App, id: &str) -> Result<Value> {
    let rpc = app.rpc();
    let chain = Chain {
        rpc: &rpc,
        miner: app.cfg.miner_wallet.clone(),
        watch: app.cfg.watch_wallet.clone(),
    };

    let c = app
        .contracts
        .get_mut(id)
        .ok_or_else(|| anyhow!("unknown contract"))?;

    let mut refund = c.dlc_txs.refund.clone();
    let investor_sig = dlc::util::get_raw_sig_for_tx_input(
        &app.secp,
        &refund,
        0,
        &c.funding_script,
        c.fund_value,
        &app.investor.sk,
    )
    .map_err(|e| anyhow!("raw sig: {:?}", e))?;
    dlc::util::sign_multi_sig_input(
        &app.secp,
        &mut refund,
        &investor_sig,
        &app.investor.pk,
        &app.peg.sk,
        &c.funding_script,
        c.fund_value,
        0,
    )
    .map_err(|e| anyhow!("sign_multi_sig_input: {:?}", e))?;

    // refund nLockTime is a block height; mine up to it before broadcasting.
    let height = chain.block_count()? as u32;
    if height < c.refund_lock_time {
        chain.mine((c.refund_lock_time - height) as u64)?;
    }

    let refund_txid = chain.broadcast(&refund)?;
    c.status = "refunded".to_string();
    Ok(json!({ "refund_txid": refund_txid }))
}

// Fase 1: the peg_pot is real collateral sitting in the peg-side CET output
// (P2WPKH, sidecar peg key). We spend THAT output to the holders' reserve
// addresses (sum minus a network fee), signing with app.peg.sk. This replaces
// the old `sendmany` from the miner wallet (fake coins).
fn handle_distribute(app: &App, id: &str, body: &Value) -> Result<Value> {
    let rpc = app.rpc();
    let chain = Chain {
        rpc: &rpc,
        miner: app.cfg.miner_wallet.clone(),
        watch: app.cfg.watch_wallet.clone(),
    };
    let c = app
        .contracts
        .get(id)
        .ok_or_else(|| anyhow!("unknown contract"))?;
    let (peg_outpoint, peg_value) = match (c.peg_payout_outpoint, c.peg_payout_value) {
        (Some(op), Some(v)) => (op, v),
        _ => bail!("peg CET output not recorded; execute the contract first"),
    };

    let fee_rate = body["fee_rate_sats_vb"].as_u64().unwrap_or(5);
    let mut requested: Vec<(String, ScriptBuf, u64)> = Vec::new();
    for p in body["payouts"].as_array().cloned().unwrap_or_default() {
        let addr = p["address"]
            .as_str()
            .ok_or_else(|| anyhow!("distribute payout.address"))?
            .to_string();
        let sats = p["sats"]
            .as_u64()
            .ok_or_else(|| anyhow!("distribute payout.sats"))?;
        let spk = parse_address(&addr)?;
        requested.push((addr, spk, sats));
    }
    if requested.is_empty() {
        bail!("distribute: no payouts");
    }
    let total_requested: u64 = requested.iter().map(|(_, _, s)| *s).sum();
    if total_requested == 0 {
        bail!("distribute: total requested is zero");
    }

    // Estimated vsize: 11 (overhead) + 68 (1 P2WPKH input) + 31 per P2WPKH output.
    let est_vsize = 11 + 68 + 31 * requested.len() as u64;
    let fee = est_vsize * fee_rate;
    if peg_value <= fee {
        bail!("peg CET output {} too small for fee {}", peg_value, fee);
    }
    let available = peg_value - fee;

    // Scale each requested payout to the actually-spendable amount (peg output
    // minus the fee), giving the remainder to the last holder so the sum is exact.
    let mut amounts: Vec<u64> = requested
        .iter()
        .map(|(_, _, sats)| {
            ((*sats as u128) * (available as u128) / (total_requested as u128)) as u64
        })
        .collect();
    let assigned: u64 = amounts.iter().sum();
    if let Some(last) = amounts.last_mut() {
        *last += available - assigned;
    }

    let outputs: Vec<TxOut> = requested
        .iter()
        .zip(amounts.iter())
        .map(|((_, spk, _), amt)| TxOut {
            value: Amount::from_sat(*amt),
            script_pubkey: spk.clone(),
        })
        .collect();

    let mut tx = Transaction {
        version: Version::TWO,
        lock_time: LockTime::ZERO,
        input: vec![TxIn {
            previous_output: peg_outpoint,
            script_sig: ScriptBuf::new(),
            sequence: Sequence::MAX,
            witness: Witness::new(),
        }],
        output: outputs,
    };
    dlc::util::sign_p2wpkh_input(
        &app.secp,
        &app.peg.sk,
        &mut tx,
        0,
        EcdsaSighashType::All,
        Amount::from_sat(peg_value),
    )
    .map_err(|e| anyhow!("distribute sign_p2wpkh_input: {:?}", e))?;

    let txid = chain.broadcast(&tx)?;

    let actual: Vec<Value> = requested
        .iter()
        .zip(amounts.iter())
        .map(|((addr, _, _), amt)| json!({ "address": addr, "sats": *amt }))
        .collect();

    Ok(json!({ "txid": txid, "payouts": actual }))
}

// ---------------------------------------------------------------------------
// HTTP server
// ---------------------------------------------------------------------------
fn main() -> Result<()> {
    let cfg = Config::load();
    let secp = Secp256k1::new();
    let peg = Party::new(&secp, cfg.peg_sk);
    let investor = Party::new(&secp, cfg.investor_sk);
    let port = cfg.port;

    let mut app = App {
        cfg,
        secp,
        peg,
        investor,
        contracts: HashMap::new(),
        seq: 0,
    };

    {
        let rpc = app.rpc();
        let chain = Chain {
            rpc: &rpc,
            miner: app.cfg.miner_wallet.clone(),
            watch: app.cfg.watch_wallet.clone(),
        };
        chain.ensure().context("ensure chain")?;
    }

    let server = Server::http(("0.0.0.0", port))
        .map_err(|e| anyhow!("bind {}: {}", port, e))?;
    eprintln!("[dlc-node] listening on :{}", port);

    for mut request in server.incoming_requests() {
        let method = request.method().clone();
        let url = request.url().to_string();
        let mut body_str = String::new();
        let _ = request.as_reader().read_to_string(&mut body_str);
        let body: Value = serde_json::from_str(&body_str).unwrap_or(Value::Null);

        let result = route(&mut app, &method, &url, &body);
        let response = match result {
            Ok(v) => Response::from_string(v.to_string())
                .with_header(json_header())
                .with_status_code(200),
            Err(e) => {
                eprintln!("[dlc-node] error {} {}: {:?}", method, url, e);
                Response::from_string(json!({ "error": e.to_string() }).to_string())
                    .with_header(json_header())
                    .with_status_code(400)
            }
        };
        let _ = request.respond(response);
    }
    Ok(())
}

fn json_header() -> tiny_http::Header {
    tiny_http::Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap()
}

fn route(app: &mut App, method: &Method, url: &str, body: &Value) -> Result<Value> {
    let path = url.split('?').next().unwrap_or(url);
    let parts: Vec<&str> = path.trim_matches('/').split('/').collect();
    match (method, parts.as_slice()) {
        (Method::Get, ["info"]) => handle_info(app),
        (Method::Post, ["contracts"]) => handle_create(app, body),
        (Method::Get, ["contracts", id]) => handle_get(app, id),
        (Method::Post, ["contracts", id, "execute"]) => handle_execute(app, id, body),
        (Method::Post, ["contracts", id, "refund"]) => handle_refund(app, id),
        (Method::Post, ["contracts", id, "distribute"]) => handle_distribute(app, id, body),
        _ => bail!("not found: {} {}", method.as_str(), path),
    }
}
