// Core-only validation of the hyperbola contract construction (no cfd-js needed).
const http = require("http");
const core = require("@node-dlc/core");
const msg = require("@node-dlc/messaging");
const { buildHyperbolaContractInfo, fitK, pegPayoutAt } = require("./server");

function pythiaForce(price) {
  return new Promise((resolve, reject) => {
    const mat = (Math.floor(Date.now() / 1000 / 60) + 3) * 60;
    const iso = new Date(mat * 1000).toISOString();
    const data = JSON.stringify({ maturation: iso, price });
    const req = http.request({ host: "127.0.0.1", port: 8000, path: "/v1/force", method: "POST",
      headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data) } },
      (res) => { let b = ""; res.on("data", c => b += c); res.on("end", () => resolve(JSON.parse(b))); });
    req.on("error", reject); req.write(data); req.end();
  });
}

(async () => {
  const ann = (await pythiaForce(55000)).announcement;
  const offer = 10_000_000, accept = 10_000_000, total = offer + accept;
  // FloorEUR-like sampled points (peg pot decreasing with price), peg=50000.
  const points = [
    { outcome: 1, peg_sats: total, investor_sats: 0 },
    { outcome: 25000, peg_sats: total, investor_sats: 0 },
    { outcome: 50000, peg_sats: 10_000_000, investor_sats: 10_000_000 },
    { outcome: 75000, peg_sats: 6_666_666, investor_sats: 13_333_334 },
    { outcome: 100000, peg_sats: 5_000_000, investor_sats: 15_000_000 },
    { outcome: 1048575, peg_sats: 0, investor_sats: total },
  ];
  console.log("fitK =", fitK(points, total), "(expect ~5e11: 50000*10M)");

  const ci = buildHyperbolaContractInfo(ann, points, total, 2, 20);
  console.log("ci.validate() OK; totalCollateral =", ci.totalCollateral.toString());

  const pf = ci.contractDescriptor.payoutFunction;
  const ri = ci.contractDescriptor.roundingIntervals;
  const cets = core.HyperbolaPayoutCurve.computePayouts(pf, ci.totalCollateral, ri);
  let total_cets = 0;
  for (const g of cets) total_cets += core.groupByIgnoringDigits(g.indexFrom, g.indexTo, 2, 20).length;
  console.log("payout groups =", cets.length, "-> total CETs =", total_cets);
  console.log("peg payout @ 25000 (low) =", cets.find(g => Number(g.indexTo) >= 25000 && Number(g.indexFrom) <= 25000).payout.toString());
  console.log("peg payout @ 100000 (high) =", cets.find(g => Number(g.indexTo) >= 100000 && Number(g.indexFrom) <= 100000).payout.toString());
  console.log("pegPayoutAt(55000) from samples =", pegPayoutAt(points, 55000, total));
})().catch(e => { console.log("ERR:", e.message); console.log(e.stack); });
