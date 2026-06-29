// Refund discriminator: create a DLC, mine past refund locktime, broadcast refund.
// Refund spends the same 2-of-2 funding with plain (non-adaptor) sigs from both
// parties. If this succeeds while execute fails, the bug is isolated to adaptor
// decryption; if it also fails NULLFAIL, the funding/CET signing itself is broken.
const http = require("http");
const { execSync } = require("child_process");

function req(host, port, path, method, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const r = http.request(
      { host, port, path, method, headers: { "Content-Type": "application/json", ...(data ? { "Content-Length": Buffer.byteLength(data) } : {}) } },
      (res) => { let b = ""; res.on("data", (c) => (b += c)); res.on("end", () => { try { resolve({ code: res.statusCode, json: b ? JSON.parse(b) : null }); } catch (e) { resolve({ code: res.statusCode, text: b }); } }); }
    );
    r.on("error", reject);
    if (data) r.write(data);
    r.end();
  });
}
const pythia = (p, b) => req("127.0.0.1", 8000, p, "POST", b);
const shim = (p, m, b) => req("127.0.0.1", 8090, p, m, b);
const cli = (args) => execSync(`docker compose -f docker-compose.regtest.yml exec -T bitcoind bitcoin-cli -regtest -rpcuser=regtest -rpcpassword=regtest ${args}`, { cwd: "/Users/mat/dev/eur-token-poc" }).toString().trim();

(async () => {
  const height = parseInt(cli("getblockcount"), 10);
  console.log("height:", height);
  const refundLock = height + 3;

  const mat = (Math.floor(Date.now() / 1000 / 60) + 3) * 60;
  const iso = new Date(mat * 1000).toISOString();
  const forced = (await pythia("/v1/force", { maturation: iso, price: 55000 })).json;
  const ann = forced.announcement;

  const offer = 10_000_000, accept = 10_000_000, total = offer + accept;
  const payouts = [
    { outcome: 1, peg_sats: total, investor_sats: 0 },
    { outcome: 50000, peg_sats: 10_000_000, investor_sats: 10_000_000 },
    { outcome: 75000, peg_sats: 6_666_666, investor_sats: 13_333_334 },
    { outcome: 1048575, peg_sats: 0, investor_sats: total },
  ];

  const create = await shim("/contracts", "POST", {
    oracle_announcement: JSON.stringify(ann), payouts,
    offer_collateral_sats: offer, accept_collateral_sats: accept,
    refund_locktime: refundLock, fee_rate_sats_vb: 4, contract_id: "deal-refund",
  });
  console.log("CREATE:", create.code, JSON.stringify(create.json));
  if (create.code !== 200) return;

  // mine past the refund locktime (miner wallet)
  const addr = cli("-rpcwallet=miner getnewaddress");
  cli(`-rpcwallet=miner generatetoaddress 6 ${addr}`);
  console.log("mined to height:", cli("getblockcount"));

  const refund = await shim("/contracts/deal-refund/refund", "POST", {});
  console.log("REFUND:", refund.code, JSON.stringify(refund.json));
})().catch((e) => console.log("TEST ERR:", e.message));
