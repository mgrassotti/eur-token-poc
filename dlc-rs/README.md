# dlc-node — Rust DLC sidecar (`mat_dlc` + HTTP)

REST sidecar that drives the FloorEUR numeric DLC on **regtest** against a
[Pythia](https://github.com/dlc-markets/pythia) oracle. It is the on-chain DLC
engine for the PoC.

The crate also exports **`mat_dlc`** (`rlib` + `cdylib`): unsigned contract
construction, on-device adaptor signing, and watchtower CET/refund completion
**without party secret keys**. Flutter loads the cdylib via
`mobile/packages/mat_dlc`.

## Why Rust / rust-dlc

Pinned to the **same commit Pythia uses** (`p2pderivatives/rust-dlc` @
`fe0e0764`) with `secp256k1-zkp 0.11`. Oracle and node share the adaptor-point
math, so EXECUTE verifies.

## HTTP contract (matches `Dlc::NodeClient`)

| Method | Path | Returns |
|---|---|---|
| GET | `/info` | `{ pubkey, network, watchtower }` |
| POST | `/contracts` | unsigned funding + `sign_package` (+ adaptor sigs when `auto_sign`) |
| GET | `/contracts/:id` | `{ contract_id, status, funding_txid, sign_package, … }` |
| POST | `/contracts/:id/adaptor_sigs` | store one party's CET adaptor sigs + refund sig |
| POST | `/contracts/:id/execute` | CET from oracle attestation + both adaptor sigs (close package) |
| POST | `/contracts/:id/refund` | pre-signed refund |
| POST | `/contracts/:id/distribute` | legacy fan-out (sidecar keys; unused for direct-payout CETs) |

## Model

- **Production / mobile:** the sidecar builds the 2-of-2 and CET set from
  **client fund pubkeys** and **user payout addresses**. It does **not** hold
  party seckeys. Each phone adaptor-signs the CET set; the close package
  (both adaptor sigs + refund) is stored on the relay watchtower.
- **Regtest `auto_sign: true`:** the sidecar adaptor-signs with
  `PEG_SECKEY` / `INVESTOR_SECKEY` (test keys only) so integration specs can
  activate without Flutter.
- CET outputs pay saver/investor addresses directly (`direct_payout`).
- At maturity the watchtower decrypts **both** adaptor signatures with the
  oracle attestation (`complete_cet`) and broadcasts. No user key required.
- If nobody publishes a CET before `refund_locktime`, the pre-signed refund
  is broadcast.

## Config (env)

| Var | Default |
|---|---|
| `PORT` | `8090` |
| `BITCOIND_RPC_URL` | `http://127.0.0.1:18443` |
| `BITCOIND_RPC_USER` / `BITCOIND_RPC_PASSWORD` | `regtest` / `regtest` |
| `MINER_WALLET` / `WATCH_WALLET` | `miner` / `dlcwatch` |
| `PEG_SECKEY` / `INVESTOR_SECKEY` | deterministic **regtest** keys (NOT for real funds; `auto_sign` only) |
| `DLC_ROUNDING_BUCKETS` | `20` |

## Build / run

```bash
docker compose -f docker-compose.regtest.yml up -d --build dlc-node
# native lib for Flutter:
cargo build --release --manifest-path dlc-rs/Cargo.toml
```

## FFI (`mat_dlc_json`)

Ops: `fund_keys`, `sign_adaptor`, `complete_cet`, `complete_refund`.
Caller frees the result with `mat_dlc_string_free`.
