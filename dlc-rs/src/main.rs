//! REST sidecar around `mat_dlc`. Builds unsigned DLC contracts from client
//! fund pubkeys; CET/refund execution uses uploaded adaptor signatures (no
//! party keys on the server except the optional test-only `auto_sign` path).

use std::collections::HashMap;
use std::str::FromStr;

use anyhow::{anyhow, bail, Context, Result};
use bitcoin::absolute::LockTime;
use bitcoin::sighash::EcdsaSighashType;
use bitcoin::transaction::Version;
use bitcoin::{
    Amount, Network, OutPoint, ScriptBuf, Sequence, Transaction, TxIn, TxOut, Txid, Witness,
};
use secp256k1_zkp::{All, PublicKey, Secp256k1, SecretKey};
use serde_json::{json, Value};
use tiny_http::{Method, Response, Server};

use mat_dlc::sign::{
    complete_cet, complete_refund, hex_pk, parse_pk, serialize_tx, PartySignatures, SignPackage,
};
use mat_dlc::{auto_sign_both, build_unsigned_contract, BuildInput, BuildRequest};

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
    network: Network,
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
            peg_sk: sk_from_env(
                "PEG_SECKEY",
                "1111111111111111111111111111111111111111111111111111111111111111",
            ),
            investor_sk: sk_from_env(
                "INVESTOR_SECKEY",
                "2222222222222222222222222222222222222222222222222222222222222222",
            ),
            rounding_buckets: env_or("DLC_ROUNDING_BUCKETS", "20").parse().unwrap_or(20),
            network: Network::Regtest,
        }
    }
}

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

struct Party {
    sk: SecretKey,
    pk: PublicKey,
}

impl Party {
    fn new(secp: &Secp256k1<All>, sk: SecretKey) -> Self {
        let pk = PublicKey::from_secret_key(secp, &sk);
        Party { sk, pk }
    }
}

struct Chain<'a> {
    rpc: &'a Rpc,
    miner: String,
    watch: String,
}

impl<'a> Chain<'a> {
    fn ensure(&self) -> Result<()> {
        self.rpc.try_call("createwallet", json!([self.miner]), None);
        self.rpc.try_call("loadwallet", json!([self.miner]), None);
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

struct Contract {
    sign_package: SignPackage,
    offerer_sigs: Option<PartySignatures>,
    acceptor_sigs: Option<PartySignatures>,
    funding_txid: String,
    funding_vout: u64,
    refund_lock_time: u32,
    status: String,
    peg_payout_outpoint: Option<OutPoint>,
    peg_payout_value: Option<u64>,
    investor_payout_outpoint: Option<OutPoint>,
    investor_payout_value: Option<u64>,
    investor_payout_spk: ScriptBuf,
    investor_payout_address: String,
    peg_payout_spk: ScriptBuf,
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

fn handle_info(app: &App) -> Result<Value> {
    Ok(json!({
        "pubkey": hex_pk(&app.peg.pk),
        "network": "regtest",
        "watchtower": true,
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

fn parse_inputs(v: &Value) -> Result<Vec<BuildInput>> {
    let arr = v.as_array().ok_or_else(|| anyhow!("inputs must be an array"))?;
    let mut out = Vec::with_capacity(arr.len());
    for it in arr {
        let txid = Txid::from_str(it["txid"].as_str().ok_or_else(|| anyhow!("input.txid"))?)?;
        let vout = it["vout"].as_u64().ok_or_else(|| anyhow!("input.vout"))? as u32;
        let amount = it["amount_sats"]
            .as_u64()
            .ok_or_else(|| anyhow!("input.amount_sats"))?;
        out.push(BuildInput {
            txid,
            vout,
            amount_sats: amount,
        });
    }
    Ok(out)
}

fn handle_create(app: &mut App, body: &Value) -> Result<Value> {
    let rpc = app.rpc();
    let chain = Chain {
        rpc: &rpc,
        miner: app.cfg.miner_wallet.clone(),
        watch: app.cfg.watch_wallet.clone(),
    };
    chain.ensure().context("ensure chain")?;

    let ann_str = match &body["oracle_announcement"] {
        Value::String(s) => s.clone(),
        v => v.to_string(),
    };
    let auto_sign = body["auto_sign"].as_bool().unwrap_or(false);
    let (peg_pk, investor_pk) = if auto_sign {
        (hex_pk(&app.peg.pk), hex_pk(&app.investor.pk))
    } else {
        (
            body["peg_fund_pubkey"]
                .as_str()
                .ok_or_else(|| anyhow!("peg_fund_pubkey"))?
                .to_string(),
            body["investor_fund_pubkey"]
                .as_str()
                .ok_or_else(|| anyhow!("investor_fund_pubkey"))?
                .to_string(),
        )
    };
    let _ = parse_pk(&peg_pk)?;
    let _ = parse_pk(&investor_pk)?;

    let peg_payout_address = body["peg_payout_address"]
        .as_str()
        .ok_or_else(|| anyhow!("peg_payout_address"))?
        .to_string();
    let investor_payout_address = body["investor_payout_address"]
        .as_str()
        .ok_or_else(|| anyhow!("investor_payout_address"))?
        .to_string();

    let height = chain.block_count()? as u32;
    let req = BuildRequest {
        oracle_announcement: ann_str,
        offer_collateral_sats: body["offer_collateral_sats"]
            .as_u64()
            .ok_or_else(|| anyhow!("offer_collateral_sats"))?,
        accept_collateral_sats: body["accept_collateral_sats"]
            .as_u64()
            .ok_or_else(|| anyhow!("accept_collateral_sats"))?,
        fee_rate_sats_vb: body["fee_rate_sats_vb"].as_u64().unwrap_or(5),
        rounding_buckets: app.cfg.rounding_buckets,
        points: parse_points(&body["payouts"]),
        peg_inputs: parse_inputs(&body["peg_inputs"]).context("peg_inputs")?,
        investor_inputs: parse_inputs(&body["investor_inputs"]).context("investor_inputs")?,
        peg_change_address: body["peg_change_address"]
            .as_str()
            .ok_or_else(|| anyhow!("peg_change_address"))?
            .to_string(),
        investor_change_address: body["investor_change_address"]
            .as_str()
            .ok_or_else(|| anyhow!("investor_change_address"))?
            .to_string(),
        peg_payout_address: peg_payout_address.clone(),
        investor_payout_address: investor_payout_address.clone(),
        peg_fund_pubkey: peg_pk,
        investor_fund_pubkey: investor_pk,
        refund_locktime: body["refund_locktime"].as_u64().unwrap_or(0) as u32,
        cet_lock_time: height,
        network: app.cfg.network,
    };

    eprintln!("[dlc-node] create: unsigned DLC with client fund pubkeys");
    let built = build_unsigned_contract(&req)?;

    let mut offerer_sigs = None;
    let mut acceptor_sigs = None;
    if auto_sign {
        eprintln!("[dlc-node] create: auto_sign (regtest keys, not for production)");
        let (offer, accept) = auto_sign_both(
            &app.secp,
            &built.sign_package,
            &app.peg.sk,
            &app.investor.sk,
        )?;
        offerer_sigs = Some(offer);
        acceptor_sigs = Some(accept);
    }

    let id = body["contract_id"]
        .as_str()
        .map(|s| s.to_string())
        .unwrap_or_else(|| {
            app.seq += 1;
            format!("dlc-{}", app.seq)
        });

    let sign_package = built.sign_package.clone();
    let offerer_out = offerer_sigs.clone();
    let acceptor_out = acceptor_sigs.clone();
    app.contracts.insert(
        id.clone(),
        Contract {
            sign_package: built.sign_package,
            offerer_sigs,
            acceptor_sigs,
            funding_txid: built.funding_txid.clone(),
            funding_vout: built.funding_vout,
            refund_lock_time: built.refund_lock_time,
            status: "pending_funding".to_string(),
            peg_payout_outpoint: None,
            peg_payout_value: None,
            investor_payout_outpoint: None,
            investor_payout_value: None,
            investor_payout_spk: built.investor_payout_spk,
            investor_payout_address,
            peg_payout_spk: built.peg_payout_spk,
        },
    );

    let mut out = json!({
        "contract_id": id,
        "funding_txid": built.funding_txid,
        "funding_vout": built.funding_vout,
        "funding_tx_hex": built.funding_tx_hex,
        "status": "pending_funding",
        "sign_package": sign_package,
        "direct_payout": true,
    });
    if let (Some(offer), Some(accept)) = (&offerer_out, &acceptor_out) {
        out["offerer_adaptor_sigs"] = json!(offer.adaptor_sigs);
        out["offerer_refund_sig"] = json!(offer.refund_sig);
        out["acceptor_adaptor_sigs"] = json!(accept.adaptor_sigs);
        out["acceptor_refund_sig"] = json!(accept.refund_sig);
    }
    Ok(out)
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
        "funding_vout": c.funding_vout,
        "sign_package": c.sign_package,
        "offerer_signed": c.offerer_sigs.is_some(),
        "acceptor_signed": c.acceptor_sigs.is_some(),
    }))
}

fn parse_party_sigs(v: &Value) -> Result<PartySignatures> {
    let adaptor_sigs = v["adaptor_sigs"]
        .as_array()
        .ok_or_else(|| anyhow!("adaptor_sigs"))?
        .iter()
        .map(|s| {
            s.as_str()
                .map(|x| x.to_string())
                .ok_or_else(|| anyhow!("adaptor sig not string"))
        })
        .collect::<Result<Vec<_>>>()?;
    let refund_sig = v["refund_sig"]
        .as_str()
        .ok_or_else(|| anyhow!("refund_sig"))?
        .to_string();
    Ok(PartySignatures {
        adaptor_sigs,
        refund_sig,
    })
}

fn handle_adaptor_sigs(app: &mut App, id: &str, body: &Value) -> Result<Value> {
    let c = app
        .contracts
        .get_mut(id)
        .ok_or_else(|| anyhow!("unknown contract"))?;
    let role = body["role"].as_str().ok_or_else(|| anyhow!("role"))?;
    let sigs = parse_party_sigs(body)?;
    match role {
        "offer" | "offerer" | "peg" | "saver" | "borrower" => c.offerer_sigs = Some(sigs),
        "accept" | "acceptor" | "investor" => c.acceptor_sigs = Some(sigs),
        other => bail!("unknown role {other}"),
    }
    Ok(json!({
        "contract_id": id,
        "offerer_signed": c.offerer_sigs.is_some(),
        "acceptor_signed": c.acceptor_sigs.is_some(),
    }))
}

fn close_package_from_body(body: &Value) -> Result<Option<(SignPackage, PartySignatures, PartySignatures)>> {
    if body["sign_package"].is_null() {
        return Ok(None);
    }
    let package: SignPackage = serde_json::from_value(body["sign_package"].clone())
        .context("sign_package")?;
    let offerer = parse_party_sigs(&json!({
        "adaptor_sigs": body["offerer_adaptor_sigs"],
        "refund_sig": body["offerer_refund_sig"],
    }))?;
    let acceptor = parse_party_sigs(&json!({
        "adaptor_sigs": body["acceptor_adaptor_sigs"],
        "refund_sig": body["acceptor_refund_sig"],
    }))?;
    Ok(Some((package, offerer, acceptor)))
}

fn record_cet_outputs(c: &mut Contract, cet: &Transaction, cet_txid: &str) -> Result<(i64, i64)> {
    let cet_txid_parsed = Txid::from_str(cet_txid)?;
    let peg_sats = match cet
        .output
        .iter()
        .enumerate()
        .find(|(_, o)| o.script_pubkey == c.peg_payout_spk)
    {
        Some((idx, txout)) => {
            let value = txout.value.to_sat();
            c.peg_payout_outpoint = Some(OutPoint {
                txid: cet_txid_parsed,
                vout: idx as u32,
            });
            c.peg_payout_value = Some(value);
            value as i64
        }
        None => 0,
    };
    let investor_sats = match cet
        .output
        .iter()
        .enumerate()
        .find(|(_, o)| o.script_pubkey == c.investor_payout_spk)
    {
        Some((idx, txout)) => {
            let value = txout.value.to_sat();
            c.investor_payout_outpoint = Some(OutPoint {
                txid: cet_txid_parsed,
                vout: idx as u32,
            });
            c.investor_payout_value = Some(value);
            value as i64
        }
        None => 0,
    };
    Ok((peg_sats, investor_sats))
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

    let (package, offerer, acceptor) = if let Some(pack) = close_package_from_body(body)? {
        pack
    } else {
        let c = app
            .contracts
            .get(id)
            .ok_or_else(|| anyhow!("unknown contract"))?;
        let offerer = c
            .offerer_sigs
            .clone()
            .ok_or_else(|| anyhow!("offerer adaptor signatures missing"))?;
        let acceptor = c
            .acceptor_sigs
            .clone()
            .ok_or_else(|| anyhow!("acceptor adaptor signatures missing"))?;
        (c.sign_package.clone(), offerer, acceptor)
    };

    let (cet, outcome, pkg_peg, pkg_inv) = complete_cet(
        &package,
        &offerer.adaptor_sigs,
        &acceptor.adaptor_sigs,
        &att_val,
    )?;
    let cet_txid = chain.broadcast(&cet)?;

    let (peg_sats, investor_sats) = if let Some(c) = app.contracts.get_mut(id) {
        let recorded = record_cet_outputs(c, &cet, &cet_txid)?;
        c.status = "executed".to_string();
        recorded
    } else {
        (pkg_peg as i64, pkg_inv as i64)
    };

    Ok(json!({
        "cet_txid": cet_txid,
        "outcome": outcome,
        "peg_sats": peg_sats,
        "investor_sats": investor_sats,
        "cet_hex": serialize_tx(&cet),
    }))
}

fn handle_refund(app: &mut App, id: &str, body: &Value) -> Result<Value> {
    let rpc = app.rpc();
    let chain = Chain {
        rpc: &rpc,
        miner: app.cfg.miner_wallet.clone(),
        watch: app.cfg.watch_wallet.clone(),
    };

    let (package, offerer, acceptor, refund_lock_time) = if let Some((pkg, off, acc)) =
        close_package_from_body(body)?
    {
        (pkg.clone(), off, acc, pkg.refund_lock_time)
    } else {
        let c = app
            .contracts
            .get(id)
            .ok_or_else(|| anyhow!("unknown contract"))?;
        let offerer = c
            .offerer_sigs
            .clone()
            .ok_or_else(|| anyhow!("offerer refund signature missing"))?;
        let acceptor = c
            .acceptor_sigs
            .clone()
            .ok_or_else(|| anyhow!("acceptor refund signature missing"))?;
        (
            c.sign_package.clone(),
            offerer,
            acceptor,
            c.refund_lock_time,
        )
    };

    let refund = complete_refund(&package, &offerer.refund_sig, &acceptor.refund_sig)?;
    let height = chain.block_count()? as u32;
    if height < refund_lock_time {
        chain.mine((refund_lock_time - height) as u64)?;
    }
    let refund_txid = chain.broadcast(&refund)?;
    if let Some(c) = app.contracts.get_mut(id) {
        c.status = "refunded".to_string();
    }
    Ok(json!({ "refund_txid": refund_txid, "refund_hex": serialize_tx(&refund) }))
}

fn parse_address_spk(s: &str) -> Result<ScriptBuf> {
    mat_dlc::sign::parse_address(s, Network::Regtest)
}

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
    let investor_input = match (c.investor_payout_outpoint, c.investor_payout_value) {
        (Some(op), Some(v)) if v > 0 => Some((op, v)),
        _ => None,
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
        let spk = parse_address_spk(&addr)?;
        requested.push((addr, spk, sats));
    }
    if requested.is_empty() {
        bail!("distribute: no payouts");
    }
    let total_requested: u64 = requested.iter().map(|(_, _, s)| *s).sum();
    if total_requested == 0 {
        bail!("distribute: total requested is zero");
    }

    let input_count = if investor_input.is_some() { 2 } else { 1 };
    let total_inputs = peg_value + investor_input.map(|(_, v)| v).unwrap_or(0);
    let base_output_count = requested.len() as u64;
    let with_investor_output_vsize = 11 + 68 * input_count + 31 * (base_output_count + 1);
    let mut fee = with_investor_output_vsize * fee_rate;
    let mut investor_payout_sats = total_inputs
        .checked_sub(total_requested + fee)
        .ok_or_else(|| anyhow!("distribute: CET outputs cannot cover exact holder payouts plus fee"))?;

    let include_investor_output = investor_payout_sats >= 546;
    if !include_investor_output {
        let holder_only_vsize = 11 + 68 * input_count + 31 * base_output_count;
        fee = holder_only_vsize * fee_rate;
        investor_payout_sats = total_inputs
            .checked_sub(total_requested + fee)
            .ok_or_else(|| anyhow!("distribute: CET outputs cannot cover exact holder payouts plus fee"))?;
    }

    let mut outputs: Vec<TxOut> = requested
        .iter()
        .map(|(_, spk, amt)| TxOut {
            value: Amount::from_sat(*amt),
            script_pubkey: spk.clone(),
        })
        .collect();
    if include_investor_output {
        outputs.push(TxOut {
            value: Amount::from_sat(investor_payout_sats),
            script_pubkey: c.investor_payout_spk.clone(),
        });
    }

    // Direct-payout CETs pay user addresses; the sidecar cannot spend them.
    // This path only works for legacy contracts whose CET outputs used sidecar keys.
    let mut tx = Transaction {
        version: Version::TWO,
        lock_time: LockTime::ZERO,
        input: {
            let mut inputs = vec![TxIn {
                previous_output: peg_outpoint,
                script_sig: ScriptBuf::new(),
                sequence: Sequence::MAX,
                witness: Witness::new(),
            }];
            if let Some((investor_outpoint, _)) = investor_input {
                inputs.push(TxIn {
                    previous_output: investor_outpoint,
                    script_sig: ScriptBuf::new(),
                    sequence: Sequence::MAX,
                    witness: Witness::new(),
                });
            }
            inputs
        },
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
    if let Some((_, investor_value)) = investor_input {
        dlc::util::sign_p2wpkh_input(
            &app.secp,
            &app.investor.sk,
            &mut tx,
            1,
            EcdsaSighashType::All,
            Amount::from_sat(investor_value),
        )
        .map_err(|e| anyhow!("distribute investor sign_p2wpkh_input: {:?}", e))?;
    }

    let txid = chain.broadcast(&tx)?;
    let actual: Vec<Value> = requested
        .iter()
        .map(|(addr, _, amt)| json!({ "address": addr, "sats": *amt }))
        .collect();

    Ok(json!({
        "txid": txid,
        "payouts": actual,
        "investor_payout_sats": investor_payout_sats,
        "investor_payout_address": c.investor_payout_address,
    }))
}

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

    let server = Server::http(("0.0.0.0", port)).map_err(|e| anyhow!("bind {}: {}", port, e))?;
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
        (Method::Post, ["contracts", id, "adaptor_sigs"]) => handle_adaptor_sigs(app, id, body),
        (Method::Post, ["contracts", id, "execute"]) => handle_execute(app, id, body),
        (Method::Post, ["contracts", id, "refund"]) => handle_refund(app, id, body),
        (Method::Post, ["contracts", id, "distribute"]) => handle_distribute(app, id, body),
        _ => bail!("not found: {} {}", method.as_str(), path),
    }
}
