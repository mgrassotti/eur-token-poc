# dlc-node — Rust DLC sidecar (rust-dlc)

REST sidecar that drives the FloorEUR numeric DLC on **regtest** against a
[Pythia](https://github.com/dlc-markets/pythia) oracle. It is the on-chain DLC
engine for the PoC and a drop-in replacement for the legacy node-dlc/cfd-dlc-js
shim (`../dlc-shim`).

## Why Rust / rust-dlc

The previous engine (`cfd-dlc-js`, AtomicFinance) produced CETs that bitcoind
rejected with `NULLFAIL` on EXECUTE: its ECDSA-adaptor signature-point math did
not agree with the `rust-dlc` attestations emitted by Pythia.

This sidecar is built on **`rust-dlc`** (`dlc` + `dlc-trie` + `dlc-messages`)
pinned to the **same commit Pythia uses** (`p2pderivatives/rust-dlc` @
`fe0e0764`) with `secp256k1-zkp 0.11`. Oracle and node therefore share the exact
same crypto code: the adaptor point and the oracle s-value decomposition
(`signatures_to_secret`) agree byte-for-byte, so EXECUTE is valid.

## HTTP contract (matches `Dlc::NodeClient`)

| Method | Path | Returns |
|---|---|---|
| GET | `/info` | `{ pubkey, network }` |
| POST | `/contracts` | `{ contract_id, funding_txid, funding_vout, funding_address, status }` |
| GET | `/contracts/:id` | `{ contract_id, status, funding_txid, funding_vout }` |
| POST | `/contracts/:id/execute` | `{ cet_txid, outcome, peg_sats, investor_sats }` |
| POST | `/contracts/:id/refund` | `{ refund_txid }` |
| POST | `/contracts/:id/distribute` | `{ txid, payouts }` |

## Model (PoC)

- Holds **both** parties' keys (peg = offerer, investor = acceptor) and drives
  the whole offer/accept/sign handshake in-process.
- Funds the 2-of-2 from a bitcoind regtest wallet (one deterministic key per
  party, used as funding-input + 2-of-2 fund key).
- Numeric digit-decomposition via `MultiOracleTrie`; FloorEUR `peg = K/price`
  curve sampled, rounded (`DLC_ROUNDING_BUCKETS`) and coalesced into one CET per
  constant-payout interval.
- At maturity, decrypts the accept-side adaptor signature with the oracle
  attestation and co-signs with the peg fund key (`dlc::sign_cet`).

## Config (env)

| Var | Default |
|---|---|
| `PORT` | `8090` |
| `BITCOIND_RPC_URL` | `http://127.0.0.1:18443` |
| `BITCOIND_RPC_USER` / `BITCOIND_RPC_PASSWORD` | `regtest` / `regtest` |
| `MINER_WALLET` / `WATCH_WALLET` | `miner` / `dlcwatch` |
| `PEG_SECKEY` / `INVESTOR_SECKEY` | deterministic regtest keys (NOT for real funds) |
| `DLC_ROUNDING_BUCKETS` | `20` |

## Build / run

Via compose (profile `dlc`):

```bash
docker compose -f docker-compose.regtest.yml up -d --build dlc-node
```

End-to-end smoke tests (need bitcoind + pythia + dlc-node up):

```bash
node ../dlc-shim/roundtrip_test.js   # CREATE / EXECUTE / DISTRIBUTE
node ../dlc-shim/refund_test.js      # CREATE / REFUND
```

## Future alternative (Variant A)

A full peer-to-peer DLC node — `ddk-node` (dlcdevkit, gRPC + Nostr transport +
Kormir oracle + BDK wallet + esplora) remains a valid future direction. It is
heavier (two nodes + relay + esplora) but also `rust-dlc`-based, so the concepts
here carry over.
