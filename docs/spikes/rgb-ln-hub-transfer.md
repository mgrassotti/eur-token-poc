# Spike: Alice → MAT hub → Claude RGB-LN transfer

> **Parked (2026-07-18).** Product default for user↔user EURT is **L1 RGB** again (unknown counterparties / inbound liquidity). This branch keeps the working hub PoC for later LSP-style work or Phase 5 learnings. Active payments: `feature/mobile-relay-phase1` (L1 `/sendrgb`).

**Date:** 2026-07-16  
**Branch:** `spike/rgb-ln-hub-poc` (was developed on `feature/ln-zero-fee-transfers`)  
**Exit criteria:** Alice→Claude EURT payment on regtest with **no `/sendrgb` for the payment** (channel opens / hub seeding may still use L1).

## Topology

```
Alice RLN (:3001)  --RGB channel-->  Hub/issuer RLN (:3005)  --RGB channel-->  Claude RLN (:3003)
```

Matches RLN’s `vendor/rgb-lightning-node/src/test/multi_hop.rs`.

## L1 → LN for Alice’s EURT

`POST /openchannel` with `asset_id` + `asset_amount` locks off-channel RGB into the channel. Spendable off-channel drops; `offchain_outbound` rises. That is the migrate step — not a separate API.

## Hub liquidity for Claude inbound

The hub must lock **its own** off-channel EURT into the Claude edge before it can route. PoC seeds hub by an L1 RGB transfer Alice→hub when needed (`HubChannelService#seed_hub_from_sender!`), and mirrors that in `ProjectionService.apply_hub_seed!`.

**First-send economics (PoC):** for payment `X`, Rails provisions **2X** hub seed + **2X** Alice→hub channel so a second send of `X` needs no further L1. After the first payment Alice’s spendable drops by **3X** (2X seed + 2X channel − X still in channel after paying X… net 3X), Claude +X. Subsequent sends of X (while capacity remains) are LN-only.

**Follow-up:** pre-fund hub from treasury so Alice does not pay liquidity capital.

## PoC knobs

| Env | Default | Meaning |
|-----|---------|---------|
| `RGB_TRANSFER_VIA_LN` | `0` | `1` → `Rgb::LnTransferService` via hub |
| `RLN_HUB_URL` | issuer `http://127.0.0.1:3005` | Hub API |
| `RLN_HUB_PEER_ADDR` | `rln-issuer:9735` | Hub peer on compose network |

Channel opens use `capacity_sat=100_000`, `push_msat=3_500_000`, `fee_base_msat=0`, `fee_proportional_millionths=0`.

## How to run

```bash
./bin/regtest up   # if needed
RGB_TRANSFER_VIA_LN=1 bundle exec rspec spec/integration/rgb_ln_hub_transfer_spec.rb
```

## Services added

- `Rgb::HubSetupService` — init/unlock/fund hub
- `Rgb::HubChannelService` — ensure Alice outbound + Claude inbound via hub
- `Rgb::LnTransferService` — `lninvoice` + `sendpayment`
- `Rgb::TransferService` — switches on `RGB_TRANSFER_VIA_LN`

## Fees observed (expected)

| Step | Fee type |
|------|----------|
| Hub seed Alice→hub (2× amount on first setup) | L1 RGB (`/sendrgb`) once when seeding |
| Alice→hub / hub→Claude open | L1 channel funding once per edge |
| Alice→Claude payment | LN only (no `/sendrgb`) |
| Second payment (capacity left) | LN only |

## Open follow-ups

1. Pre-fund hub from treasury so Alice does not pay 2× liquidity.
2. Persist channel metadata vs `list_channels` only.
3. Surface “opening channel…” in mobile when Rails opens edges synchronously.
4. Confirm whether public RGB channels + zero fees are enough for multi-hop pathfinding on this RLN build (integration spec is the check).
