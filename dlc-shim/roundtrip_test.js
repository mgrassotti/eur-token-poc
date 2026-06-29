// End-to-end round-trip against the running shim container + Pythia.
// Usage: node roundtrip_test.js  (expects shim on :8090, pythia on :8000)
const http = require("http");
function req(host, port, path, method, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const r = http.request({ host, port, path, method,
      headers: { "Content-Type": "application/json", ...(data ? { "Content-Length": Buffer.byteLength(data) } : {}) } },
      (res) => { let b = ""; res.on("data", c => b += c); res.on("end", () => { try { resolve({ code: res.statusCode, json: b ? JSON.parse(b) : null }); } catch (e) { resolve({ code: res.statusCode, text: b }); } }); });
    r.on("error", reject); if (data) r.write(data); r.end();
  });
}
const pythia = (p, b) => req("127.0.0.1", 8000, p, "POST", b);
const shim = (p, m, b) => req("127.0.0.1", 8090, p, m, b);

(async () => {
  console.log("info:", JSON.stringify((await shim("/info", "GET")).json));
  const mat = (Math.floor(Date.now() / 1000 / 60) + 3) * 60;
  const iso = new Date(mat * 1000).toISOString();
  const forced = (await pythia("/v1/force", { maturation: iso, price: 55000 })).json;
  const ann = forced.announcement, att = forced.attestation;
  console.log("forced eventId:", att.eventId);

  const offer = 10_000_000, accept = 10_000_000, total = offer + accept;
  const payouts = [
    { outcome: 1, peg_sats: total, investor_sats: 0 },
    { outcome: 50000, peg_sats: 10_000_000, investor_sats: 10_000_000 },
    { outcome: 75000, peg_sats: 6_666_666, investor_sats: 13_333_334 },
    { outcome: 1048575, peg_sats: 0, investor_sats: total },
  ];

  const t0 = Date.now();
  const create = await shim("/contracts", "POST", {
    oracle_announcement: JSON.stringify(ann), payouts,
    offer_collateral_sats: offer, accept_collateral_sats: accept,
    refund_locktime: 5000, fee_rate_sats_vb: 4, contract_id: "deal-rt",
  });
  console.log(`CREATE (${((Date.now() - t0) / 1000).toFixed(1)}s):`, create.code, JSON.stringify(create.json));
  if (create.code !== 200) return;

  const exec = await shim("/contracts/deal-rt/execute", "POST", { attestation: JSON.stringify(att) });
  console.log("EXECUTE:", exec.code, JSON.stringify(exec.json));

  const dist = await shim("/contracts/deal-rt/distribute", "POST", {
    payouts: [{ address: "bcrt1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080", sats: 5_000_000 }], fee_rate_sats_vb: 4,
  });
  console.log("DISTRIBUTE:", dist.code, JSON.stringify(dist.json));
})().catch(e => console.log("TEST ERR:", e.message));
