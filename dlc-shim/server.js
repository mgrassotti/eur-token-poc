"use strict";

// REST shim that turns the node-dlc / @atomicfinance DLC library into the HTTP
// service the Ruby backend (Dlc::NodeClient) already speaks. It owns the on-chain
// DLC machinery on regtest: it builds a numeric (digit-decomposition) FloorEUR
// contract from a Pythia oracle announcement, funds the 2-of-2, broadcasts the
// funding tx and — at maturity — executes the CET unlocked by the oracle
// attestation (or the timelocked refund). PoC scope: the shim holds BOTH parties'
// keys (peg = offerer, investor = acceptor) and drives the full handshake
// in-process.
//
// Endpoint contract (matches Dlc::NodeClient):
//   GET  /info                       -> { pubkey, network }
//   POST /contracts                  -> { contract_id, funding_txid, funding_vout, funding_address, status }
//   GET  /contracts/:id              -> { contract_id, status, funding_txid, funding_vout }
//   POST /contracts/:id/execute      -> { cet_txid, outcome, peg_sats, investor_sats }
//   POST /contracts/:id/refund       -> { refund_txid }
//   POST /contracts/:id/distribute   -> { txid, payouts }

const express = require("express");
const http = require("http");
const Client = require("@atomicfinance/client").default;
const { BitcoinRpcProvider } = require("@atomicfinance/bitcoin-rpc-provider");
const { BitcoinJsWalletProvider } = require("@atomicfinance/bitcoin-js-wallet-provider");
const BitcoinDlcProvider = require("@atomicfinance/bitcoin-dlc-provider").default;
const { BitcoinNetworks } = require("bitcoin-network");
const msg = require("@node-dlc/messaging");
const core = require("@node-dlc/core");
const BigNumber = require("bignumber.js").default || require("bignumber.js");

// cfd-dlc-js (native, via cfd-js) is the on-chain DLC tx engine the provider
// drives. It is injected into BitcoinDlcProvider; without it CfdLoaded() spins
// forever. Requires a Node version with a published cfd-js prebuilt (18/20/22).
let cfddlcjs = null;
try {
  cfddlcjs = require("cfd-dlc-js");
} catch (e) {
  console.error("[dlc-shim] cfd-dlc-js unavailable:", e.message);
}

// cfd-js carries the *base* cfd methods (GetPubkeyFromPrivkey, CreateSignatureHash,
// CalculateEcSignature, CreateRawTransaction, ...). cfd-dlc-js only exports the DLC
// methods, and the atomicfinance Client resolves base methods through the provider
// stack, so we register a thin provider exposing every cfd-js function below.
let cfdjs = null;
try {
  cfdjs = require("cfd-js");
} catch (e) {
  console.error("[dlc-shim] cfd-js unavailable:", e.message);
}

class CfdProvider {
  setClient(client) {
    this.client = client;
  }
}
if (cfdjs) {
  for (const name of Object.keys(cfdjs)) {
    if (typeof cfdjs[name] === "function" && name !== "setClient") {
      CfdProvider.prototype[name] = function (...args) {
        return cfdjs[name](...args);
      };
    }
  }
}

// PoC: we run our own regtest oracle, so skip the announcement signature check
// (known node-dlc <-> rust-dlc announcement serialization incompatibility). The
// DLC cryptography still binds to the oracle nonces and attestation signatures.
msg.OracleAnnouncement.prototype.validate = function () {};


// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const PORT = parseInt(process.env.PORT || "8090", 10);
const RPC_URL = process.env.BITCOIND_RPC_URL || "http://127.0.0.1:18443";
const RPC_USER = process.env.BITCOIND_RPC_USER || "regtest";
const RPC_PASS = process.env.BITCOIND_RPC_PASSWORD || "regtest";
const MINER_WALLET = process.env.MINER_WALLET || "miner";
const WATCH_WALLET = process.env.WATCH_WALLET || "dlcwatch";
// Deterministic regtest mnemonics (NOT for any real funds).
const PEG_MNEMONIC = process.env.PEG_MNEMONIC ||
  "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const INVESTOR_MNEMONIC = process.env.INVESTOR_MNEMONIC ||
  "legal winner thank year wave sausage worth useful legal winner thank yellow";

const NET = BitcoinNetworks.bitcoin_regtest;
const FUND_BUFFER_SATS = 2_000_000n; // extra per party to cover on-chain fees
const COIN = 100_000_000;

const { hostname: RPC_HOST, port: RPC_PORT } = new URL(RPC_URL);

// ---------------------------------------------------------------------------
// bitcoind JSON-RPC
// ---------------------------------------------------------------------------
function rpc(method, params = [], wallet = null) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ jsonrpc: "1.0", id: "shim", method, params });
    const path = wallet ? `/wallet/${wallet}` : "/";
    const req = http.request(
      {
        host: RPC_HOST,
        port: RPC_PORT || 18443,
        path,
        method: "POST",
        headers: {
          "Content-Type": "text/plain",
          "Content-Length": Buffer.byteLength(body),
          Authorization: "Basic " + Buffer.from(`${RPC_USER}:${RPC_PASS}`).toString("base64"),
        },
      },
      (res) => {
        let b = "";
        res.on("data", (c) => (b += c));
        res.on("end", () => {
          try {
            const j = JSON.parse(b);
            j.error ? reject(new Error(`${method}: ${JSON.stringify(j.error)}`)) : resolve(j.result);
          } catch (e) {
            reject(new Error(`${method}: ${b.slice(0, 200)}`));
          }
        });
      }
    );
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}
async function tryRpc(method, params, wallet) {
  try {
    return await rpc(method, params, wallet);
  } catch (e) {
    return { _err: e.message };
  }
}

const btc = (sats) => Number(BigInt(sats)) / COIN;
const toSats = (n) => BigInt(Math.round(Number(n) * COIN));

// ---------------------------------------------------------------------------
// Chain setup: a spendable miner wallet + a watch-only descriptor wallet
// (bitcoind 28 has no legacy wallets, so input discovery uses importdescriptors
// + listunspent on a descriptor watch-only wallet).
// ---------------------------------------------------------------------------
async function ensureChain() {
  await tryRpc("createwallet", [MINER_WALLET]);
  await tryRpc("loadwallet", [MINER_WALLET]);
  await tryRpc("createwallet", [WATCH_WALLET, true, true, "", false, true]); // disable_privkeys, blank, descriptors
  await tryRpc("loadwallet", [WATCH_WALLET]);

  const balance = await rpc("getbalance", [], MINER_WALLET).catch(() => 0);
  if (Number(balance) < 50) {
    const addr = await rpc("getnewaddress", [], MINER_WALLET);
    await rpc("generatetoaddress", [101, addr]);
  }
}

async function minerAddress() {
  return rpc("getnewaddress", [], MINER_WALLET);
}
async function mine(n = 1) {
  return rpc("generatetoaddress", [n, await minerAddress()]);
}

// Import an address into the watch-only wallet so listunspent can see its UTXOs.
async function watchAddress(address) {
  const di = await rpc("getdescriptorinfo", [`addr(${address})`]);
  await rpc("importdescriptors", [[{ desc: di.descriptor, timestamp: "now", internal: false }]], WATCH_WALLET);
}

// ---------------------------------------------------------------------------
// atomicfinance clients (peg = offerer, investor = acceptor)
// ---------------------------------------------------------------------------
function makeClient(mnemonic) {
  const client = new Client();
  client.addProvider(
    new BitcoinRpcProvider({
      uri: `${RPC_URL.replace(/\/$/, "")}/wallet/${WATCH_WALLET}`,
      username: RPC_USER,
      password: RPC_PASS,
      network: NET,
    })
  );
  client.addProvider(
    new BitcoinJsWalletProvider({
      network: NET,
      mnemonic,
      baseDerivationPath: "m/84'/1'/0'",
      addressType: "bech32",
    })
  );
  // Must sit below BitcoinDlcProvider in the stack so its base cfd methods are
  // resolvable by the DLC provider (getMethod searches lower-index providers).
  client.addProvider(new CfdProvider());
  client.addProvider(new BitcoinDlcProvider(NET, cfddlcjs));
  return client;
}

const peg = makeClient(PEG_MNEMONIC);
const investor = makeClient(INVESTOR_MNEMONIC);

// Fund a client's fresh address with collateral + fee buffer so input selection
// has something to spend; returns the funded address.
async function fundClient(client, collateralSats) {
  const addrObj = await client.wallet.getUnusedAddress();
  const address = addrObj.address || addrObj;
  await watchAddress(address);
  const amount = btc(BigInt(collateralSats) + FUND_BUFFER_SATS);
  await rpc("sendtoaddress", [address, amount], MINER_WALLET);
  await mine(1);
  return address;
}

function txHex(tx) {
  if (!tx) return null;
  if (typeof tx.hex === "string") return tx.hex;
  if (typeof tx.toHex === "function") return tx.toHex();
  if (typeof tx.serialize === "function") return tx.serialize().toString("hex");
  return null;
}
async function broadcast(tx) {
  const hex = txHex(tx);
  if (!hex) throw new Error("cannot serialize transaction");
  const txid = await rpc("sendrawtransaction", [hex]);
  await mine(1);
  return txid;
}

// ---------------------------------------------------------------------------
// Contract construction (numeric FloorEUR descriptor from Pythia announcement)
// ---------------------------------------------------------------------------
// Coarse payout rounding keeps the CET set small (cfd-js builds one CET per
// digit-decomposition message; a 20-digit event with fine rounding produces
// thousands). Rounding payouts to ~1/ROUNDING_BUCKETS of the collateral keeps
// it to a few dozen — adequate for the PoC.
const ROUNDING_BUCKETS = parseInt(process.env.DLC_ROUNDING_BUCKETS || "20", 10);

// FloorEUR peg payout is liability/price = K/price — a hyperbola, which is the
// single payout-curve shape the @atomicfinance provider supports (the polynomial
// path enumerates per-outcome and is unusably slow). We fit K from the sampled
// points and build the covered-call-style hyperbola so the offerer (peg) gets
// K/price (full pot at low prices, ~0 at high prices), exactly the FloorEUR split.
function fitK(points, total) {
  const interior = points
    .map((p) => ({ o: Number(p.outcome), s: Number(p.peg_sats) }))
    .filter((p) => p.o > 0 && p.s > 0 && p.s < total);
  if (interior.length === 0) {
    const first = points[0] || { outcome: 1, peg_sats: total };
    return Math.max(1, Number(first.outcome)) * total;
  }
  interior.sort((a, b) => Math.abs(a.s - total / 2) - Math.abs(b.s - total / 2));
  return interior[0].o * interior[0].s;
}

function bn(v) {
  return new BigNumber(String(v));
}

// Build a single-hyperbola payout function with totalCollateral fixed to `total`
// (= offer + accept). Mirrors @node-dlc/core CoveredCall but pins totalCollateral
// and constructs the message objects directly (the hyperbola piece JSON does not
// round-trip its left/right endpoints).
function buildHyperbolaContractInfo(annJson, points, total, base, nbDigits) {
  const K = fitK(points, total);
  const maxOutcome = BigInt(Math.pow(base, nbDigits) - 1);
  const a = bn(1), b = bn(0), c = bn(0), d = bn(K);
  const tmp = new core.HyperbolaPayoutCurve(a, b, c, d, bn(0), bn(0));
  const maxOutcomePayout = tmp.getPayout(maxOutcome).integerValue();
  const curve = new core.HyperbolaPayoutCurve(a, b, c, d, bn(0), maxOutcomePayout.negated());

  const tc = BigInt(total);
  const piece = curve.toPayoutCurvePiece();
  piece.leftEndPoint = { eventOutcome: 0n, outcomePayout: tc, extraPrecision: 0 };
  piece.rightEndPoint = { eventOutcome: maxOutcome, outcomePayout: 0n, extraPrecision: 0 };

  const payoutFunction = new msg.PayoutFunction();
  payoutFunction.payoutFunctionPieces = [
    { endPoint: { eventOutcome: maxOutcome, outcomePayout: 0n, extraPrecision: 0 }, payoutCurvePiece: piece },
  ];
  payoutFunction.lastEndpoint = { eventOutcome: maxOutcome, outcomePayout: 0n, extraPrecision: 0 };

  const roundingMod = Math.max(1, Math.floor(total / ROUNDING_BUCKETS));
  const descriptor = new msg.NumericalDescriptor();
  descriptor.numDigits = nbDigits;
  descriptor.payoutFunction = payoutFunction;
  descriptor.roundingIntervals = msg.RoundingIntervals.fromJSON({
    intervals: [{ beginInterval: 0, roundingMod }],
  });

  const oracleInfo = new msg.SingleOracleInfo();
  oracleInfo.announcement = msg.OracleAnnouncement.fromJSON(annJson);

  const ci = new msg.SingleContractInfo();
  ci.totalCollateral = tc;
  ci.contractDescriptor = descriptor;
  ci.oracleInfo = oracleInfo;
  ci.validate();
  return ci;
}

// Offerer (peg) payout at a given outcome, from the sampled points (step/linear).
function pegPayoutAt(points, outcome, total) {
  const sorted = [...points]
    .map((p) => ({ outcome: Number(p.outcome), peg: Number(p.peg_sats) }))
    .sort((a, b) => a.outcome - b.outcome);
  if (sorted.length === 0) return total;
  if (outcome <= sorted[0].outcome) return Math.min(total, sorted[0].peg);
  if (outcome >= sorted[sorted.length - 1].outcome) return Math.max(0, sorted[sorted.length - 1].peg);
  for (let i = 0; i < sorted.length - 1; i++) {
    const a = sorted[i], b = sorted[i + 1];
    if (outcome >= a.outcome && outcome <= b.outcome) {
      const t = (outcome - a.outcome) / (b.outcome - a.outcome || 1);
      return Math.round(a.peg + t * (b.peg - a.peg));
    }
  }
  return sorted[sorted.length - 1].peg;
}

function digitsToInt(values, base) {
  return values.reduce((acc, d) => acc * base + parseInt(d, 10), 0);
}

// ---------------------------------------------------------------------------
// In-memory contract store
// ---------------------------------------------------------------------------
const contracts = new Map();
let seq = 0;

// ---------------------------------------------------------------------------
// HTTP server
// ---------------------------------------------------------------------------
const app = express();
app.use(express.json({ limit: "2mb" }));

function fail(res, e, code = 400) {
  console.error("[dlc-shim]", e && e.stack ? e.stack : e);
  res.status(code).json({ error: e && e.message ? e.message : String(e) });
}

app.get("/info", async (_req, res) => {
  try {
    const addr = await peg.wallet.getUnusedAddress();
    res.json({ pubkey: addr.publicKey ? addr.publicKey.toString("hex") : addr.address, network: "regtest" });
  } catch (e) {
    fail(res, e, 500);
  }
});

app.post("/contracts", async (req, res) => {
  try {
    const {
      oracle_announcement,
      payouts,
      offer_collateral_sats,
      accept_collateral_sats,
      refund_locktime,
      fee_rate_sats_vb,
      contract_id,
    } = req.body;

    const annJson = typeof oracle_announcement === "string" ? JSON.parse(oracle_announcement) : oracle_announcement;
    const offer = Number(offer_collateral_sats);
    const accept = Number(accept_collateral_sats);
    const total = offer + accept;
    const feeRate = BigInt(fee_rate_sats_vb || 5);

    const dd = annJson.oracleEvent.eventDescriptor.digitDecompositionEvent;
    const base = dd.base || 2;
    const nbDigits = dd.nbDigits;

    const step = (m) => console.log(`[dlc-shim] /contracts ${req.body.contract_id || ""}: ${m}`);
    step("build contract info");
    const ci = buildHyperbolaContractInfo(annJson, payouts, total, base, nbDigits);

    step("fund peg");
    await fundClient(peg, offer);
    step("fund investor");
    await fundClient(investor, accept);

    const height = await rpc("getblockcount", []);
    const cetLocktime = height;
    const refundLocktime = Math.max(Number(refund_locktime) || height + 1000, height + 2);

    step("createDlcOffer");
    const dlcOffer = await peg.dlc.createDlcOffer(ci, BigInt(offer), feeRate, cetLocktime, refundLocktime);
    step("acceptDlcOffer");
    const acceptRes = await investor.dlc.acceptDlcOffer(dlcOffer);
    const dlcAccept = acceptRes.dlcAccept;
    step("signDlcAccept");
    const signRes = await peg.dlc.signDlcAccept(dlcOffer, dlcAccept);
    const dlcSign = signRes.dlcSign;
    const dlcTxs = signRes.dlcTransactions;

    step("finalizeDlcSign");
    const fundTx = await investor.dlc.finalizeDlcSign(dlcOffer, dlcAccept, dlcSign, dlcTxs);
    step("broadcast funding");
    const fundingTxid = await broadcast(fundTx);
    step("funded " + fundingTxid);

    const id = contract_id || `dlc-${++seq}`;
    contracts.set(id, {
      id,
      dlcOffer,
      dlcAccept,
      dlcSign,
      dlcTxs,
      annJson,
      points: payouts,
      total,
      fundingTxid,
      status: "funded",
    });

    res.json({
      contract_id: id,
      funding_txid: fundingTxid,
      funding_vout: 0,
      funding_address: null,
      status: "funded",
    });
  } catch (e) {
    fail(res, e);
  }
});

app.get("/contracts/:id", (req, res) => {
  const c = contracts.get(req.params.id);
  if (!c) return res.status(404).json({ error: "unknown contract" });
  res.json({ contract_id: c.id, status: c.status, funding_txid: c.fundingTxid, funding_vout: 0 });
});

app.post("/contracts/:id/execute", async (req, res) => {
  try {
    const c = contracts.get(req.params.id);
    if (!c) return res.status(404).json({ error: "unknown contract" });

    const att = typeof req.body.attestation === "string" ? JSON.parse(req.body.attestation) : req.body.attestation;
    const base = c.annJson.oracleEvent.eventDescriptor.digitDecompositionEvent.base || 2;
    const values = att.values || att.outcomes;
    const oracleAttestation = msg.OracleAttestation.fromJSON({
      eventId: att.eventId || c.annJson.oracleEvent.eventId,
      oraclePublicKey: c.annJson.oraclePublicKey,
      signatures: att.signatures,
      outcomes: values,
    });

    // Decrypt the accept-side CET adaptor signature with the oracle attestation and
    // co-sign with the peg fund key (node-dlc canonical execute path).
    //
    // KNOWN BLOCKER: against a Pythia/rust-dlc oracle this CET is rejected by
    // bitcoind with NULLFAIL ("Signature must be zero for failed CHECKMULTISIG").
    // Everything around it verifies: the funding tx + refund (same 2-of-2) broadcast
    // fine, the accept adaptor passes cfd-dlc VerifyCetAdaptorSignature, the attested
    // digits match the located CET group, and each oracle scalar satisfies
    // s_i*G == cfd ComputeSigPoint(P, R_i, digit_i). The decrypted CET signature is
    // nonetheless invalid, pointing to a cfd-dlc-js (atomicfinance) vs rust-dlc
    // ECDSA-adaptor signature-point incompatibility in this dependency version.
    const cetTx = await peg.dlc.execute(c.dlcOffer, c.dlcAccept, c.dlcSign, c.dlcTxs, oracleAttestation, true);
    const cetTxid = await broadcast(cetTx);

    const outcome = digitsToInt(values, base);
    const pegSats = pegPayoutAt(c.points, outcome, c.total);
    const investorSats = c.total - pegSats;

    c.status = "executed";
    c.cetTxid = cetTxid;

    res.json({ cet_txid: cetTxid, outcome, peg_sats: pegSats, investor_sats: investorSats });
  } catch (e) {
    fail(res, e);
  }
});

app.post("/contracts/:id/refund", async (req, res) => {
  try {
    const c = contracts.get(req.params.id);
    if (!c) return res.status(404).json({ error: "unknown contract" });
    const refundTx = await peg.dlc.refund(c.dlcOffer, c.dlcAccept, c.dlcSign, c.dlcTxs);
    const refundTxid = await broadcast(refundTx);
    c.status = "refunded";
    res.json({ refund_txid: refundTxid });
  } catch (e) {
    fail(res, e);
  }
});

// PoC: realize the peg_pot fan-out as a single on-chain payout to holders,
// funded from the miner wallet (a real tx + txid; the CET already moved the pot
// to the peg side economically).
app.post("/contracts/:id/distribute", async (req, res) => {
  try {
    const c = contracts.get(req.params.id);
    if (!c) return res.status(404).json({ error: "unknown contract" });
    const payouts = req.body.payouts || [];
    const outputs = {};
    for (const p of payouts) {
      const addr = p.address;
      if (!addr) continue;
      outputs[addr] = (outputs[addr] || 0) + btc(p.sats);
    }
    let txid = null;
    if (Object.keys(outputs).length > 0) {
      txid = await rpc("sendmany", ["", outputs], MINER_WALLET);
      await mine(1);
    }
    res.json({ txid, payouts });
  } catch (e) {
    fail(res, e);
  }
});

if (require.main === module) {
  (async () => {
    await ensureChain();
    app.listen(PORT, "0.0.0.0", () => console.log(`[dlc-shim] listening on :${PORT}`));
  })().catch((e) => {
    console.error("[dlc-shim] startup failed:", e);
    process.exit(1);
  });
}

module.exports = { buildHyperbolaContractInfo, fitK, pegPayoutAt, digitsToInt };
